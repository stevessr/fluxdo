// SPDX-License-Identifier: Apache-2.0
// Headless OpenXR PICO camera bridge. Only a user-initiated, foreground scan
// may acquire frames. No frame or credential is written to disk or logcat.
#define XR_USE_PLATFORM_ANDROID
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include "pico_camera_image.h"
#include <android/log.h>
#include <jni.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
std::mutex scanMutex;
std::mutex statusMutex;
std::atomic<bool> cancelled{false};
std::atomic<jlong> activeScan{0};
struct ScanToken {
    explicit ScanToken(jlong token) { activeScan = token; }
    ~ScanToken() { activeScan = 0; }
};
std::string lastError;
void status(const char* text) {
    std::lock_guard<std::mutex> lock(statusMutex);
    lastError = text;  // Never write decoded QR contents to diagnostics.
}
bool expired(Clock::time_point deadline) {
    return cancelled.load() || Clock::now() >= deadline;
}
template <class T>
bool load(XrInstance instance, const char* name, T& fn) {
    return xrGetInstanceProcAddr(instance, name,
        reinterpret_cast<PFN_xrVoidFunction*>(&fn)) == XR_SUCCESS && fn;
}
bool waitForFuture(XrInstance instance, XrFutureEXT future,
                   PFN_xrPollFutureEXT poll, Clock::time_point deadline) {
    while (!expired(deadline)) {
        XrFuturePollInfoEXT info{XR_TYPE_FUTURE_POLL_INFO_EXT};
        info.future = future;
        XrFuturePollResultEXT state{XR_TYPE_FUTURE_POLL_RESULT_EXT};
        const XrResult result = poll(instance, &info, &state);
        if (XR_FAILED(result)) { status("XR future poll failed"); return false; }
        if (state.state == XR_FUTURE_STATE_READY_EXT) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    status("XR camera initialization cancelled or timed out");
    return false;
}
// RAII frees resources on every return path (including scan timeout).
struct XrState {
    XrInstance instance{XR_NULL_HANDLE};
    XrSession session{XR_NULL_HANDLE};
    XrCameraDevicePICO device{XR_NULL_HANDLE};
    XrCameraCaptureSessionPICO capture{XR_NULL_HANDLE};
    PFN_xrDestroyCameraDevicePICO destroyDevice{};
    PFN_xrDestroyCameraCaptureSessionPICO destroyCapture{};
    PFN_xrEndCameraCapturePICO endCapture{};
    bool capturing{false};
    ~XrState() {
        if (capturing && endCapture) endCapture(capture);
        if (capture != XR_NULL_HANDLE && destroyCapture) destroyCapture(capture);
        if (device != XR_NULL_HANDLE && destroyDevice) destroyDevice(device);
        if (session != XR_NULL_HANDLE) xrDestroySession(session);
        if (instance != XR_NULL_HANDLE) xrDestroyInstance(instance);
    }
};

jstring run(JNIEnv* env, jobject activity, jlong timeoutMillis, jlong token) {
    std::unique_lock<std::mutex> singleScan(scanMutex, std::try_to_lock);
    if (!singleScan.owns_lock()) { status("Another XR scan is active"); return nullptr; }
    cancelled = false;
    ScanToken active(token);
    const auto deadline = Clock::now() +
        std::chrono::milliseconds(std::clamp(static_cast<long long>(timeoutMillis), 1000LL, 30000LL));

    JavaVM* vm = nullptr;
    if (env->GetJavaVM(&vm) != JNI_OK || !vm) {
        status("JVM unavailable"); return nullptr;
    }
    PFN_xrInitializeLoaderKHR initializeLoader = nullptr;
    if (xrGetInstanceProcAddr(XR_NULL_HANDLE, "xrInitializeLoaderKHR",
        reinterpret_cast<PFN_xrVoidFunction*>(&initializeLoader)) != XR_SUCCESS || !initializeLoader) {
        status("OpenXR Android loader unavailable"); return nullptr;
    }
    XrLoaderInitInfoAndroidKHR loader{XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR};
    loader.applicationVM = vm;
    loader.applicationContext = activity;
    if (XR_FAILED(initializeLoader(reinterpret_cast<const XrLoaderInitInfoBaseHeaderKHR*>(&loader)))) {
        status("OpenXR loader initialization failed"); return nullptr;
    }

    const char* const required[] = {
        XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME,
        "XR_MND_headless", "XR_EXT_future", "XR_PICO_camera_image"
    };
    uint32_t extCount = 0;
    if (XR_FAILED(xrEnumerateInstanceExtensionProperties(nullptr, 0, &extCount, nullptr)) ||
        extCount > 4096) { status("XR extension enumeration failed"); return nullptr; }
    std::vector<XrExtensionProperties> extensions(extCount);
    for (auto& item : extensions) item.type = XR_TYPE_EXTENSION_PROPERTIES;
    if (XR_FAILED(xrEnumerateInstanceExtensionProperties(nullptr, extCount, &extCount, extensions.data()))) {
        status("XR extensions unavailable"); return nullptr;
    }
    for (const char* needed : required) {
        if (std::none_of(extensions.begin(), extensions.end(), [needed](const auto& x) {
            return std::strcmp(x.extensionName, needed) == 0;
        })) {
            if (std::strcmp(needed, "XR_PICO_camera_image") == 0)
                status("PICO firmware does not expose XR_PICO_camera_image");
            else if (std::strcmp(needed, "XR_MND_headless") == 0)
                status("Headless OpenXR unsupported by firmware");
            else status("Required OpenXR extension unavailable");
            return nullptr;
        }
    }

    XrState xr;
    XrInstanceCreateInfoAndroidKHR androidInfo{XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR};
    androidInfo.applicationVM = vm;
    androidInfo.applicationActivity = activity;
    XrInstanceCreateInfo instanceInfo{XR_TYPE_INSTANCE_CREATE_INFO};
    instanceInfo.next = &androidInfo;
    std::strncpy(instanceInfo.applicationInfo.applicationName, "Fluxdo XR QR", XR_MAX_APPLICATION_NAME_SIZE - 1);
    std::strncpy(instanceInfo.applicationInfo.engineName, "Fluxdo", XR_MAX_ENGINE_NAME_SIZE - 1);
    instanceInfo.applicationInfo.apiVersion = XR_CURRENT_API_VERSION;
    instanceInfo.applicationInfo.applicationVersion = 1;
    instanceInfo.applicationInfo.engineVersion = 1;
    instanceInfo.enabledExtensionCount = sizeof(required) / sizeof(required[0]);
    instanceInfo.enabledExtensionNames = required;
    if (XR_FAILED(xrCreateInstance(&instanceInfo, &xr.instance))) {
        status("XR instance creation failed"); return nullptr;
    }
    XrSystemGetInfo getSystem{XR_TYPE_SYSTEM_GET_INFO};
    getSystem.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    XrSystemId systemId = XR_NULL_SYSTEM_ID;
    if (XR_FAILED(xrGetSystem(xr.instance, &getSystem, &systemId))) {
        status("No active XR headset system"); return nullptr;
    }
    XrSessionCreateInfo sessionInfo{XR_TYPE_SESSION_CREATE_INFO};
    sessionInfo.systemId = systemId; // XR_MND_headless: no graphics binding
    if (XR_FAILED(xrCreateSession(xr.instance, &sessionInfo, &xr.session))) {
        status("Headless XR session rejected (2D app may lack XR entitlement)"); return nullptr;
    }

    PFN_xrPollFutureEXT poll = nullptr;
    PFN_xrEnumerateAvailableCamerasPICO enumerate = nullptr;
    PFN_xrCreateCameraDeviceAsyncPICO createDevice = nullptr;
    PFN_xrCreateCameraDeviceCompletePICO completeDevice = nullptr;
    PFN_xrCreateCameraCaptureSessionAsyncPICO createCapture = nullptr;
    PFN_xrCreateCameraCaptureSessionCompletePICO completeCapture = nullptr;
    PFN_xrBeginCameraCapturePICO begin = nullptr;
    PFN_xrAcquireCameraImagePICO acquire = nullptr;
    PFN_xrGetCameraImageDataPICO imageData = nullptr;
    PFN_xrReleaseCameraImagePICO release = nullptr;
    if (!load(xr.instance, "xrPollFutureEXT", poll) ||
        !load(xr.instance, "xrEnumerateAvailableCamerasPICO", enumerate) ||
        !load(xr.instance, "xrCreateCameraDeviceAsyncPICO", createDevice) ||
        !load(xr.instance, "xrCreateCameraDeviceCompletePICO", completeDevice) ||
        !load(xr.instance, "xrDestroyCameraDevicePICO", xr.destroyDevice) ||
        !load(xr.instance, "xrCreateCameraCaptureSessionAsyncPICO", createCapture) ||
        !load(xr.instance, "xrCreateCameraCaptureSessionCompletePICO", completeCapture) ||
        !load(xr.instance, "xrDestroyCameraCaptureSessionPICO", xr.destroyCapture) ||
        !load(xr.instance, "xrBeginCameraCapturePICO", begin) ||
        !load(xr.instance, "xrEndCameraCapturePICO", xr.endCapture) ||
        !load(xr.instance, "xrAcquireCameraImagePICO", acquire) ||
        !load(xr.instance, "xrGetCameraImageDataPICO", imageData) ||
        !load(xr.instance, "xrReleaseCameraImagePICO", release)) {
        status("PICO runtime missing camera extension entry points"); return nullptr;
    }

    // A filtered camera list would require querying vendor camera properties;
    // the extension only offers color passthrough cameras in this revision.
    XrAvailableCamerasEnumerateInfoPICO filter{XR_TYPE_AVAILABLE_CAMERAS_ENUMERATE_INFO_PICO};
    uint32_t cameraCount = 0;
    if (XR_FAILED(enumerate(xr.instance, &filter, 0, &cameraCount, nullptr)) ||
        cameraCount == 0 || cameraCount > 16) {
        status("No accessible PICO passthrough cameras"); return nullptr;
    }
    std::vector<XrCameraIdPICO> cameraIds(cameraCount);
    if (XR_FAILED(enumerate(xr.instance, &filter, cameraCount, &cameraCount, cameraIds.data()))) {
        status("PICO camera enumeration failed"); return nullptr;
    }
    XrCameraDeviceCreateInfoPICO deviceInfo{XR_TYPE_CAMERA_DEVICE_CREATE_INFO_PICO};
    deviceInfo.cameraId = cameraIds[0];
    XrFutureEXT future = XR_NULL_FUTURE_EXT;
    if (XR_FAILED(createDevice(xr.instance, &deviceInfo, &future)) ||
        !waitForFuture(xr.instance, future, poll, deadline)) {
        status("PICO camera device could not be opened"); return nullptr;
    }
    XrCreateCameraDeviceCompletionPICO deviceCompletion{XR_TYPE_CREATE_CAMERA_DEVICE_COMPLETION_PICO};
    if (XR_FAILED(completeDevice(xr.instance, future, &deviceCompletion)) ||
        XR_FAILED(deviceCompletion.futureResult)) {
        status("Camera access denied, unavailable or occupied"); return nullptr;
    }
    xr.device = deviceCompletion.device;

    XrCameraCapabilityDataTransferTypePICO rawConfig{XR_TYPE_CAMERA_CAPABILITY_DATA_TRANSFER_TYPE_PICO};
    rawConfig.transferType = XR_CAMERA_DATA_TRANSFER_TYPE_RAW_BUFFER_PICO;
    XrCameraCapabilityImageFormatPICO formatConfig{XR_TYPE_CAMERA_CAPABILITY_IMAGE_FORMAT_PICO};
    formatConfig.format = XR_CAMERA_IMAGE_FORMAT_RGBA_8888_PICO;
    const XrCameraCapabilityBaseHeaderPICO* configs[] = {
        reinterpret_cast<XrCameraCapabilityBaseHeaderPICO*>(&rawConfig),
        reinterpret_cast<XrCameraCapabilityBaseHeaderPICO*>(&formatConfig)
    };
    XrCameraCaptureSessionCreateInfoPICO captureInfo{XR_TYPE_CAMERA_CAPTURE_SESSION_CREATE_INFO_PICO};
    captureInfo.camera = xr.device;
    captureInfo.configCount = 2;
    captureInfo.configs = configs;
    future = XR_NULL_FUTURE_EXT;
    if (XR_FAILED(createCapture(xr.session, &captureInfo, &future)) ||
        !waitForFuture(xr.instance, future, poll, deadline)) {
        status("PICO camera capture session unavailable"); return nullptr;
    }
    XrCreateCameraCaptureSessionCompletionPICO captureCompletion{
        XR_TYPE_CREATE_CAMERA_CAPTURE_SESSION_COMPLETION_PICO};
    if (XR_FAILED(completeCapture(xr.session, future, &captureCompletion)) ||
        XR_FAILED(captureCompletion.futureResult)) {
        status("PICO camera capture creation failed"); return nullptr;
    }
    xr.capture = captureCompletion.captureSession;
    XrCameraCaptureBeginInfoPICO beginInfo{XR_TYPE_CAMERA_CAPTURE_BEGIN_INFO_PICO};
    if (XR_FAILED(begin(xr.capture, &beginInfo))) {
        status("PICO camera refused to start capturing"); return nullptr;
    }
    xr.capturing = true;

    jclass cls = env->GetObjectClass(activity);
    if (!cls) { status("QR decoder unavailable"); return nullptr; }
    jmethodID decodeMethod = env->GetMethodID(cls, "decodeQrFrame", "([BII)Ljava/lang/String;");
    if (!decodeMethod) {
        env->ExceptionClear();
        env->DeleteLocalRef(cls);
        status("QR decoder bridge unavailable"); return nullptr;
    }
    env->DeleteLocalRef(cls);
    XrTime lastTime = 0;
    while (!expired(deadline)) {
        XrCameraImageAcquireInfoPICO acquireInfo{XR_TYPE_CAMERA_IMAGE_ACQUIRE_INFO_PICO};
        acquireInfo.lastCaptureTime = lastTime;
        XrCameraImagePICO frame{XR_TYPE_CAMERA_IMAGE_PICO};
        const XrResult res = acquire(xr.capture, &acquireInfo, &frame);
        if (res == XR_CAMERA_IMAGE_NO_UPDATE_PICO) {
            std::this_thread::sleep_for(std::chrono::milliseconds(35));
            continue;
        }
        if (XR_FAILED(res)) { status("XR frame acquisition failed"); break; }
        XrCameraImageDataRawBufferPICO pixels{XR_TYPE_CAMERA_IMAGE_DATA_RAW_BUFFER_PICO};
        const XrResult dataResult = imageData(xr.capture, frame.imageId,
            reinterpret_cast<XrCameraImageDataBaseHeaderPICO*>(&pixels));
        jstring found = nullptr;
        if (XR_SUCCEEDED(dataResult) && pixels.buffer &&
            pixels.width > 0 && pixels.height > 0 &&
            pixels.width <= 4096 && pixels.height <= 4096 &&
            pixels.bytesPerPixel >= 3 && pixels.pixelStride >= 3 &&
            pixels.pixelStride <= 16 &&
            static_cast<uint64_t>(pixels.stride) >=
                static_cast<uint64_t>(pixels.width - 1) * pixels.pixelStride + 3 &&
            static_cast<uint64_t>(pixels.bufferSize) >=
                static_cast<uint64_t>(pixels.height - 1) * pixels.stride +
                static_cast<uint64_t>(pixels.width - 1) * pixels.pixelStride + 3 &&
            pixels.bufferSize <= 64 * 1024 * 1024) {
            // Decode at <=1024 pixels to bound CPU and Java heap use.
            const uint32_t step = std::max(1u, (std::max(pixels.width, pixels.height) + 1023) / 1024);
            const uint32_t w = (pixels.width + step - 1) / step;
            const uint32_t h = (pixels.height + step - 1) / step;
            std::vector<jbyte> gray(static_cast<size_t>(w) * h);
            for (uint32_t y = 0; y < h; ++y) {
                const uint8_t* row = pixels.buffer + static_cast<size_t>(y * step) * pixels.stride;
                for (uint32_t x = 0; x < w; ++x) {
                    const uint8_t* c = row + static_cast<size_t>(x * step) * pixels.pixelStride;
                    gray[static_cast<size_t>(y) * w + x] =
                        static_cast<jbyte>((77 * c[0] + 150 * c[1] + 29 * c[2]) >> 8);
                }
            }
            jbyteArray data = env->NewByteArray(static_cast<jsize>(gray.size()));
            if (data) {
                env->SetByteArrayRegion(data, 0, static_cast<jsize>(gray.size()), gray.data());
                found = static_cast<jstring>(env->CallObjectMethod(
                    activity, decodeMethod, data, static_cast<jint>(w), static_cast<jint>(h)));
                env->DeleteLocalRef(data);
                if (env->ExceptionCheck()) { env->ExceptionClear(); found = nullptr; }
            }
        }
        release(xr.capture, frame.imageId); // Always release, even when decoding failed.
        lastTime = frame.captureTime;
        if (found) { status("QR decoded"); return found; }
        std::this_thread::sleep_for(std::chrono::milliseconds(40));
    }
    if (cancelled) status("QR scan cancelled");
    else if (Clock::now() >= deadline) status("QR scan timed out");
    return nullptr;
}
}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_github_lingyan000_fluxdo_PicoXrQrScanActivity_scanNative(
    JNIEnv* env, jobject activity, jlong timeoutMillis, jlong token) {
    return run(env, activity, timeoutMillis, token);
}

extern "C" JNIEXPORT void JNICALL
Java_com_github_lingyan000_fluxdo_PicoXrQrScanActivity_cancelNative(
    JNIEnv*, jobject, jlong token) {
    if (activeScan.load() == token) cancelled = true;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_github_lingyan000_fluxdo_PicoXrQrScanActivity_lastNativeError(
    JNIEnv* env, jobject) {
    std::lock_guard<std::mutex> lock(statusMutex);
    return env->NewStringUTF(lastError.c_str());
}
