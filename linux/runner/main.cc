#include "my_application.h"

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>

namespace {

constexpr char kRendererModeEnv[] = "FLUXDO_RENDERER_MODE";
constexpr char kRendererReadyFdEnv[] = "FLUXDO_RENDERER_READY_FD";
constexpr int kZinkStartupTimeoutMs = 30000;

volatile sig_atomic_t active_child_pid = -1;
volatile sig_atomic_t received_signal = 0;

void ForwardSignal(int signal_number) {
  received_signal = signal_number;
  const pid_t child = static_cast<pid_t>(active_child_pid);
  if (child > 0) {
    kill(child, signal_number);
  }
}

void InstallSignalForwarding() {
  struct sigaction action = {};
  action.sa_handler = ForwardSignal;
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, nullptr);
  sigaction(SIGTERM, &action, nullptr);
  sigaction(SIGHUP, &action, nullptr);
}

int WaitStatusToExitCode(int status) {
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  if (WIFSIGNALED(status)) {
    return 128 + WTERMSIG(status);
  }
  return 1;
}

bool ReadinessReceived(int fd) {
  struct pollfd descriptor = {};
  descriptor.fd = fd;
  descriptor.events = POLLIN;
  const int result = poll(&descriptor, 1, 0);
  if (result <= 0 || (descriptor.revents & POLLIN) == 0) {
    return false;
  }
  char byte = 0;
  return read(fd, &byte, 1) == 1 && byte == '1';
}

int LaunchChild(char** argv, bool use_zink, bool* first_frame_rendered) {
  int ready_pipe[2] = {-1, -1};
  if (use_zink && pipe2(ready_pipe, O_CLOEXEC) != 0) {
    std::perror("FluxDO：创建 Zink 就绪管道失败");
    return 127;
  }

  const pid_t child = fork();
  if (child < 0) {
    std::perror("FluxDO：启动 Linux 渲染进程失败");
    if (ready_pipe[0] >= 0) {
      close(ready_pipe[0]);
      close(ready_pipe[1]);
    }
    return 127;
  }

  if (child == 0) {
    if (use_zink) {
      close(ready_pipe[0]);
      const int descriptor_flags = fcntl(ready_pipe[1], F_GETFD);
      if (descriptor_flags >= 0) {
        fcntl(ready_pipe[1], F_SETFD, descriptor_flags & ~FD_CLOEXEC);
      }
      char ready_fd[16];
      std::snprintf(ready_fd, sizeof(ready_fd), "%d", ready_pipe[1]);
      setenv(kRendererModeEnv, "zink", 1);
      setenv(kRendererReadyFdEnv, ready_fd, 1);
      setenv("MESA_LOADER_DRIVER_OVERRIDE", "zink", 1);
    } else {
      unsetenv(kRendererReadyFdEnv);
      unsetenv("MESA_LOADER_DRIVER_OVERRIDE");
      unsetenv("GALLIUM_DRIVER");
      setenv(kRendererModeEnv, "fallback", 1);
    }

    execv("/proc/self/exe", argv);
    std::perror("FluxDO：执行 Linux 渲染进程失败");
    _exit(127);
  }

  active_child_pid = child;
  if (!use_zink) {
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
      if (errno == EINTR) {
        continue;
      }
      active_child_pid = -1;
      return 127;
    }
    active_child_pid = -1;
    return WaitStatusToExitCode(status);
  }

  close(ready_pipe[1]);
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::milliseconds(kZinkStartupTimeoutMs);
  int status = 0;
  bool child_exited = false;
  *first_frame_rendered = false;
  while (!child_exited && !*first_frame_rendered) {
    struct pollfd descriptor = {};
    descriptor.fd = ready_pipe[0];
    descriptor.events = POLLIN;
    const int poll_result = poll(&descriptor, 1, 100);
    if (poll_result > 0 && (descriptor.revents & POLLIN) != 0) {
      *first_frame_rendered = ReadinessReceived(ready_pipe[0]);
    }

    const pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      child_exited = true;
      break;
    }
    if (waited < 0 && errno != EINTR) {
      kill(child, SIGKILL);
      waitpid(child, &status, 0);
      child_exited = true;
      break;
    }
    if (received_signal != 0) {
      kill(child, received_signal);
    }
    if (std::chrono::steady_clock::now() >= deadline) {
      std::fprintf(stderr, "FluxDO：Zink 在 60 秒内未绘制首帧，切回默认渲染器。\n");
      kill(child, SIGKILL);
      while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
      }
      child_exited = true;
      break;
    }
  }

  close(ready_pipe[0]);
  if (*first_frame_rendered && !child_exited) {
    while (waitpid(child, &status, 0) < 0) {
      if (errno == EINTR) {
        continue;
      }
      active_child_pid = -1;
      return 127;
    }
  }
  active_child_pid = -1;
  return WaitStatusToExitCode(status);
}

int RunWithAdaptiveRenderer(char** argv) {
  std::fprintf(stderr, "FluxDO：优先尝试 Mesa Zink（Vulkan）。\n");
  bool first_frame_rendered = false;
  const int zink_status = LaunchChild(argv, true, &first_frame_rendered);
  if (received_signal != 0) {
    return 128 + received_signal;
  }
  if (zink_status == 0 && first_frame_rendered) {
    return 0;
  }

  std::fprintf(stderr,
               "FluxDO：Zink 未能成功绘制首帧或进程异常退出，重启并回退到默认 OpenGL。\n");
  return LaunchChild(argv, false, nullptr);
}

}  // namespace

int main(int argc, char** argv) {
  const char* renderer_mode = std::getenv(kRendererModeEnv);
  const char* mesa_override = std::getenv("MESA_LOADER_DRIVER_OVERRIDE");
  const char* gallium_driver = std::getenv("GALLIUM_DRIVER");
  const bool has_non_zink_override =
      (mesa_override != nullptr && mesa_override[0] != '\0' &&
       g_strcmp0(mesa_override, "zink") != 0) ||
      (gallium_driver != nullptr && gallium_driver[0] != '\0' &&
       g_strcmp0(gallium_driver, "zink") != 0);
  if (renderer_mode != nullptr || has_non_zink_override) {
    g_autoptr(MyApplication) app = my_application_new();
    return g_application_run(G_APPLICATION(app), argc, argv);
  }

  InstallSignalForwarding();
  return RunWithAdaptiveRenderer(argv);
}
