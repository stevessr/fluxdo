#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <epoxy/gl.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <string>
#include <unistd.h>

#include <glib.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)
namespace {

bool IsDrmCardEntry(const gchar* entry) {
  if (!g_str_has_prefix(entry, "card") || !g_ascii_isdigit(entry[4])) {
    return false;
  }
  for (const gchar* digit = entry + 4; *digit != '\0'; ++digit) {
    if (!g_ascii_isdigit(*digit)) {
      return false;
    }
  }
  return true;
}

struct GtkGlInfo {
  std::string vendor;
  std::string renderer;
};

GtkGlInfo GetGtkGlInfo() {
  GdkWindowAttr attributes = {};
  attributes.width = 1;
  attributes.height = 1;
  attributes.wclass = GDK_INPUT_OUTPUT;
  attributes.window_type = GDK_WINDOW_TOPLEVEL;
  GdkWindow* test_window = gdk_window_new(nullptr, &attributes, 0);
  if (test_window == nullptr) {
    return {};
  }

  GError* error = nullptr;
  GdkGLContext* context = gdk_window_create_gl_context(test_window, &error);
  GtkGlInfo info;
  if (context != nullptr && gdk_gl_context_realize(context, &error)) {
    GdkGLContext* previous_context = gdk_gl_context_get_current();
    gdk_gl_context_make_current(context);
    if (gdk_gl_context_get_current() == context) {
      const GLubyte* vendor = glGetString(GL_VENDOR);
      const GLubyte* renderer = glGetString(GL_RENDERER);
      if (vendor != nullptr) {
        info.vendor = reinterpret_cast<const gchar*>(vendor);
      }
      if (renderer != nullptr) {
        info.renderer = reinterpret_cast<const gchar*>(renderer);
      }
    }
    if (previous_context != nullptr) {
      gdk_gl_context_make_current(previous_context);
    } else {
      gdk_gl_context_clear_current();
    }
  }

  if (context != nullptr) {
    g_object_unref(context);
  }
  if (error != nullptr) {
    g_error_free(error);
  }
  gdk_window_destroy(test_window);
  g_object_unref(test_window);
  return info;
}

const gchar* DrmVendorIdForGlVendor(const std::string& gl_vendor) {
  if (g_str_has_prefix(gl_vendor.c_str(), "Intel")) {
    return "0x8086";
  }
  if (g_str_has_prefix(gl_vendor.c_str(), "NVIDIA")) {
    return "0x10de";
  }
  if (g_str_has_prefix(gl_vendor.c_str(), "AMD") ||
      g_str_has_prefix(gl_vendor.c_str(), "ATI")) {
    return "0x1002";
  }
  return nullptr;
}

const gchar* DrmVendorIdForZinkRenderer(const std::string& renderer) {
  if (renderer.find("Intel") != std::string::npos) {
    return "0x8086";
  }
  if (renderer.find("NVIDIA") != std::string::npos) {
    return "0x10de";
  }
  if (renderer.find("AMD") != std::string::npos ||
      renderer.find("ATI") != std::string::npos ||
      renderer.find("Radeon") != std::string::npos) {
    return "0x1002";
  }
  return nullptr;
}


std::string FindUniqueDrmDeviceForVendor(const gchar* vendor_id) {
  GDir* drm_dir = g_dir_open("/sys/class/drm", 0, nullptr);
  if (drm_dir == nullptr) {
    return {};
  }

  std::string selected_device;
  bool multiple_devices = false;
  const gchar* entry = nullptr;
  while ((entry = g_dir_read_name(drm_dir)) != nullptr) {
    if (!IsDrmCardEntry(entry)) {
      continue;
    }
    const std::string vendor_path =
        std::string("/sys/class/drm/") + entry + "/device/vendor";
    gchar* device_vendor = nullptr;
    if (!g_file_get_contents(vendor_path.c_str(), &device_vendor, nullptr,
                             nullptr)) {
      continue;
    }
    const bool matches = g_strcmp0(g_strstrip(device_vendor), vendor_id) == 0;
    g_free(device_vendor);
    if (!matches) {
      continue;
    }
    if (!selected_device.empty()) {
      multiple_devices = true;
      break;
    }
    selected_device = std::string("/dev/dri/") + entry;
  }
  g_dir_close(drm_dir);

  if (multiple_devices || selected_device.empty() ||
      !g_file_test(selected_device.c_str(), G_FILE_TEST_EXISTS)) {
    return {};
  }
  return selected_device;
}

void ConfigureWpeDrmDevice(const GtkGlInfo& gl_info) {
  const gchar* configured_device = g_getenv("WPE_DRM_DEVICE");
  if (configured_device != nullptr && configured_device[0] != '\0') {
    return;
  }

  const gchar* drm_vendor_id = DrmVendorIdForGlVendor(gl_info.vendor);
  if (drm_vendor_id == nullptr &&
      g_ascii_strncasecmp(gl_info.renderer.c_str(), "zink", 4) == 0) {
    drm_vendor_id = DrmVendorIdForZinkRenderer(gl_info.renderer);
  }
  if (drm_vendor_id == nullptr) {
    return;
  }
  const std::string device = FindUniqueDrmDeviceForVendor(drm_vendor_id);
  if (!device.empty() && g_setenv("WPE_DRM_DEVICE", device.c_str(), TRUE)) {
    g_message("FluxDO：WPE 与 GTK 图形设备对齐，使用 %s（%s）",
              device.c_str(), gl_info.renderer.c_str());
  }
}

}  // namespace


static void focus_flutter_view(GtkWindow* window, GtkWidget* view) {
  if (window == nullptr || view == nullptr) {
    return;
  }

  if (!gtk_widget_get_can_focus(view)) {
    gtk_widget_set_can_focus(view, TRUE);
  }

  gtk_window_set_focus(window, view);
  gtk_widget_grab_focus(view);
}

static void on_window_show(GtkWidget* widget, gpointer user_data) {
  focus_flutter_view(GTK_WINDOW(widget), GTK_WIDGET(user_data));
}

static gboolean on_window_focus_in_event(GtkWidget* widget,
                                         GdkEventFocus* event,
                                         gpointer user_data) {
  (void)event;
  focus_flutter_view(GTK_WINDOW(widget), GTK_WIDGET(user_data));
  return FALSE;
}

static void on_window_is_active_changed(GObject* object,
                                        GParamSpec* pspec,
                                        gpointer user_data) {
  (void)pspec;
  GtkWindow* window = GTK_WINDOW(object);
  if (!gtk_window_is_active(window)) {
    return;
  }
  focus_flutter_view(window, GTK_WIDGET(user_data));
}

static gboolean on_view_button_press_event(GtkWidget* widget,
                                           GdkEventButton* event,
                                           gpointer user_data) {
  (void)event;
  focus_flutter_view(GTK_WINDOW(user_data), widget);
  return FALSE;
}

static void on_flutter_first_frame(GtkWidget* widget, gpointer user_data) {
  (void)widget;
  (void)user_data;
  const gchar* descriptor_text = g_getenv("FLUXDO_RENDERER_READY_FD");
  if (descriptor_text == nullptr) {
    return;
  }

  gchar* end = nullptr;
  const long descriptor = std::strtol(descriptor_text, &end, 10);
  if (end == descriptor_text || *end != '\0' || descriptor < 0 ||
      descriptor > INT_MAX) {
    return;
  }
  const char ready = '1';
  if (write(static_cast<int>(descriptor), &ready, sizeof(ready)) == 1) {
    close(static_cast<int>(descriptor));
    g_unsetenv("FLUXDO_RENDERER_READY_FD");
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "FluxDO");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "FluxDO");
  }

  gtk_window_set_default_size(window, 1280, 720);
  const GtkGlInfo gl_info = GetGtkGlInfo();
  const gboolean zink_attempt =
      g_strcmp0(g_getenv("FLUXDO_RENDERER_MODE"), "zink") == 0;
  if (zink_attempt &&
      g_ascii_strncasecmp(gl_info.renderer.c_str(), "zink", 4) != 0) {
    g_warning("FluxDO：Zink 初始化未成功（renderer=%s），将回退到默认渲染器",
              gl_info.renderer.empty() ? "不可用" : gl_info.renderer.c_str());
    _exit(78);
  }
  if (zink_attempt) {
    g_message("FluxDO：Zink Vulkan 渲染器已就绪：%s",
              gl_info.renderer.c_str());
  }
  ConfigureWpeDrmDevice(gl_info);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_signal_connect(view, "first-frame", G_CALLBACK(on_flutter_first_frame),
                   nullptr);

  // Realize the view so Flutter can start rendering, but keep the toplevel
  // window hidden until Dart restores the saved desktop window state.
  gtk_widget_realize(GTK_WIDGET(view));

  gtk_widget_add_events(GTK_WIDGET(view), GDK_BUTTON_PRESS_MASK);
  g_signal_connect(window, "show", G_CALLBACK(on_window_show), view);
  g_signal_connect(window,
                   "focus-in-event",
                   G_CALLBACK(on_window_focus_in_event),
                   view);
  g_signal_connect(window,
                   "notify::is-active",
                   G_CALLBACK(on_window_is_active_changed),
                   view);
  g_signal_connect(
      view, "button-press-event", G_CALLBACK(on_view_button_press_event), window);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  focus_flutter_view(window, GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
