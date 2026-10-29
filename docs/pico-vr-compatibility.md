# PICO VR (PICO 4 Ultra) Android panel compatibility

Fluxdo remains a standard Flutter/Android **2D application** on PICO headsets.
It does not request an immersive XR session.

## Multiple windows

- `MainActivity` remains `singleTask` for OAuth and deep-link callbacks.
- A non-exported, resizeable `PicoVrWindowActivity` is launched with
  `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_MULTIPLE_TASK` when users select
  **Settings → PICO VR · New window**.
- Limit additional windows to **3** active secondary Flutter engines to reduce headset OOM risk; rapid taps reserve pending slots.
- Each activity has its own Flutter engine and navigation tree. The SAF file
  picker and Media3 transcoder are scoped to their activity, while memory
  pressure notifies all running engines.
- The PICO system shell controls actual placement, window count, size and
  simultaneous visibility. Android cannot force an XR shell to show floating
  panels if the firmware does not support them.
- External OAuth / account deep links continue to arrive at the main
  `singleTask` activity, not an arbitrary secondary panel.

## Camera

PICO passthrough cameras are **not equivalent to an Android Camera2 camera**.
PICO Native OpenXR SDK 3.0.0 defines `XR_PICO_camera_image` for access via
an XR session. It is distinct from Unity Integration SDK 3.4.0. Neither makes
passthrough camera images available through Android Camera2; a standard 2D
Flutter Activity does not own an XR session.

- Native capability detection enumerates the `CameraManager.cameraIdList`
  before initializing the CameraX-backed `mobile_scanner`.
- If no Android camera is enumerated, the QR login page immediately offers
  **image import** and **paste QR payload**; it does not repeatedly attempt
  a camera session that cannot start.
- If the system resolves `android.media.action.IMAGE_CAPTURE`, the QR page also
  offers **system camera capture**, processed through the same QR validation.
  This may use a vendor-provided camera app; it does **not** guarantee raw XR
  passthrough access. The camera capture option is hidden without a handler.
- If Camera2 lists a camera but the OEM blocks streaming, the existing
  scanner error view still offers image import.
- On phones with Camera2 support, the scanner is still enabled.
- If a third-party app implements the published ZXing
  `com.google.zxing.client.android.SCAN` intent and returns `SCAN_RESULT`,
  QR login also offers **Scan with another app**. The result goes through the
  same Fluxdo QR-login payload validation as all other entry points. Fluxdo
  never logs, caches or forwards the raw QR payload to diagnostics. This is
  opt-in, unavailable without a matching app, and does **not** mean PICO's
  system scanner implements ZXing.
- **Recheck cameras** invalidates the cached capabilities (for example,
  when a USB/UVC camera was connected after opening the app). The page shows
  the Android camera count and permission status. On PICO, **Try Android
  camera preview** is an opt-in diagnostic when the camera list is empty;
  it is never treated as proof of an XR passthrough API.
- **Experimental native path (PR #166)**: an opt-in, separate
  `PicoXrQrScanActivity` now creates a headless OpenXR session and attempts
  to capture PICO color camera images. PICO firmware/runtime and real-headset
  permission behavior remain unverified; this is **not** yet hardware-proven.
  Normal Android 2D Camera2 and import/paste remain independent fallbacks.

### External scanner interoperability

- Uses the publicly documented ZXing scan action, restricted to `QR_CODE`.
  Only apps registered for the action are offered; PICO system-private
  activities are not hardcoded. The user must confirm that **the chosen scanner
  app can read the login credential** before Android displays an app chooser.
  The scanner should be treated as trusted software, not a blind fallback.
- Per-Activity outstanding request is limited to one. Cancellation returns
  null; window destruction fails the pending request rather than delivering
  the next Activity's result.
- The scanner returns its decoded text to Fluxdo through an Activity result.
  The resulting string is validated as a Fluxdo login QR payload before
  attempting authentication.
- Apps with no ZXing-compatible scanner or system camera Activity continue to
  offer image import / clipboard paste. There is no misleading fake camera
  preview on headsets that expose no Android camera devices.

## Manual device matrix

1. On PICO 4 Ultra, confirm Settings shows **PICO VR · New window**.
   Open it twice; check each window navigates independently. Attempt a fourth
   secondary window and confirm the cap does not spawn an extra engine.
2. Resize/move windows in the PICO UI, switch focus, background and resume;
   verify all windows remain interactive.
3. Use the system file picker in both windows concurrently and verify each
   result returns only to its initiating Flutter route.
4. On PICO 4 Ultra with no Android Camera2 camera, open QR login: verify
   it shows the gallery/paste fallback rather than a blank camera preview.
5. Import a valid QR image / paste valid QR text and confirm the same login
   validation path works. Paste invalid text and verify no login occurs.
   If a system camera app is available, capture a QR code and verify decoding.
   If no camera capture handler exists, confirm the action is not offered.
6. Regression check on ordinary Android: main launcher/deep link login,
   Camera2 QR scan, attachment picker, transcoding, memory pressure.

Android diagnostics:

```sh
adb shell dumpsys activity activities | grep -E 'MainActivity|PicoVrWindowActivity'
adb shell dumpsys media.camera
adb logcat -s PicoVr AppLink Camera2CameraImpl
```

CI can run analyzer/build checks, but real PICO window placement and XR
camera availability require the target headset/firmware. Do not label
CI-only checks as hardware validation.

## Experimental native OpenXR QR camera (PICO 4 Ultra)

This branch implements a **headless OpenXR** scan route, separate from the
standard 2D Flutter camera and from an external camera application.

- **Entry**: QR login → "Scan with PICO XR camera". A non-exported Android
  `PicoXrQrScanActivity` requests Android CAMERA permission and starts a
  20-second foreground-only capture attempt on a dedicated thread.
- **Runtime**: Khronos OpenXR loader initializes with the JavaVM/Activity,
  enumerates instance extensions, requires
  `XR_KHR_android_create_instance`, `XR_MND_headless`,
  `XR_EXT_future`, and `XR_PICO_camera_image`, then builds an OpenXR
  headless instance/session.
- **Camera**: Enumerates PICO camera IDs, creates camera device and capture
  session via the PICO async APIs, configures raw RGBA frames, acquires
  and releases each frame. The native session is RAII-cleaned on every exit
  including permission failure, timeout, cancellation and runtime errors.
- **Decode**: Bounds-checks frame dimensions/strides/buffer lengths, converts
  to a <=1024-pixel grayscale image in memory, decodes locally via embedded
  ZXing QRCodeReader without sending pixels to a server, and returns only
  decoded text to the originating Flutter window. The existing
  `QrLoginService.parsePayload` validates its login format before use.
- **Lifecycle**: One native scan process-wide at a time. Each Activity's
  scan token isolates cancellation across concurrent windows. Per-thread error
  reporting prevents one window overwriting another window's XR diagnostics.
  Native enumeration now filters for world-facing color cameras with raw-buffer
  RGBA capture support before creating the device. Backgrounding/closing the
  Activity cancels capture; gallery and clipboard remain fallbacks.

### Hardware caveats / acceptance

PICO's documented OpenXR extension ABI and presence of physical color cameras
**do not prove** that the consumer firmware grants XR camera access from a
separate non-immersive 2D Activity. The Native SDK 3.0.0 support table lists
`XR_MND_headless` for PICO 4 Ultra but does **not** explicitly list
`XR_PICO_camera_image` as supported by the device. PICO ships its own Loader
for private extensions, whereas this branch currently uses Khronos Android
Loader 1.1.65 plus a locally isolated PICO camera extension header. The device
must establish whether this combination exposes the extension.

If the session or extension is unavailable,
the XR scanner shows an explicit error without trying private services.
This native route is not called a *verified PICO 4 Ultra fix* until an actual
headset (with its OS build recorded) has acquired a color frame and logged in
with a QR code. CI builds are only compile/static checks.

To debug without exposing login secrets:

```sh
adb shell getprop ro.pico.ota.version
adb shell getprop ro.build.fingerprint
adb shell dumpsys package com.github.lingyan000.fluxdo | grep -A4 CAMERA
adb logcat -s OpenXR-Loader PicoVr
```

Manually verify: permission denied, runtime unavailable, no camera extension,
camera occupied, app pause/resume, timeout, concurrent second window,
normal Android phone scanning, QR success/failure. Test on PICO 4 Ultra before
merging into main; native loader or XR session behavior may need adaptation.

### Native QR robustness and privacy checks

- The native image path now validates RGB layout, pixel stride, row stride,
  last-row bounds and total buffer size before touching a pixel. Up to
  8192×8192 sensor dimensions / 256 MiB of runtime-owned raw RGBA data are
  accepted, but only a bounded <=1024px grayscale plane is copied to ZXing.
- The decoder alternates **full view** and **center 50% crop** to retain QR
  module detail when the source camera image is high-resolution. ZXing tries
  regular and inverted contrast. These are best-effort improvements, not a
  guarantee of autofocus or QR visibility on the headset.
- Foreground cancellation invalidates the paused attempt's result. If the
  Activity resumes while the old native worker is unwinding, one replacement
  scan is started after it exits. Permission requests are single-flight and a
  denied permission is not immediately requested again until the user retries.
- The scanner Activity uses `FLAG_SECURE` to prevent screenshots and recent-app
  previews from capturing QR credentials. No camera frames or decoded QR values
  are written to files or logs.
- `.github/workflows/pico-vr-compatibility.yml` now compiles and executes a
  host-side C++ sanitizer test for RGBA row padding, grayscale sampling, center
  crop, downsampling and invalid camera layout rejection. Android Kotlin and
  ARM64 JNI compilation remain independent checks. No CI run can substitute
  for live PICO firmware extension enumeration.

Manual additional cases: rapidly pause/resume the QR scanner; deny permission,
retry only after explicitly pressing Try; show a QR small in the passthrough
field of view, and an inverted (light-on-dark) QR; start scans from two different
Flutter windows; verify that a paused window never accepts an old QR result.

### PICO 4 Ultra SDK acceptance checkpoints

Open **QR login → Scan with PICO XR camera** on the physical headset and
record the error text shown after a scan attempt, plus the OS version. Error
messages contain no QR contents or frames. The key stages are:

| Native error | What it proves / next check |
|---|---|
| `PICO firmware does not expose XR_PICO_camera_image` | Enumerated runtime extensions lack camera image support; verify PICO Loader and firmware rather than QR decoder. |
| `Headless OpenXR unsupported by firmware` | `XR_MND_headless` is not exposed despite its listing in the PICO SDK device matrix. |
| `Headless XR session rejected by runtime (XrResult ...)` | 2D Activity may not be allowed to own an XR session; consider an explicit XR host Activity if confirmed. |
| `PICO camera denied, unavailable or occupied (XrResult ...)` | Distinguish permission and camera contention by numeric return code. |
| `No world-facing RGB camera supporting raw RGBA capture` | No available passthrough camera meets the requested raw image configuration. |
| `QR scan timed out: received 0 frames` | Camera setup succeeded but image delivery did not; if frames were received, check image format and QR decoding. |

Official references: [Native SDK downloads](https://developer.picoxr.com/resources/?platform=native), [PICO OpenXR quickstart](https://developer.picoxr.com/document/native/openxr-sdk-quickstart/), [Native SDK extension specification](https://lf3-static.bytednsdoc.com/obj/eden-cn/sliheh7phbozbps/NativeSDK/3.0.0/NativeSdkSpec.html), [PICO extension support matrix](https://developer.picoxr.com/document/native/about-extensions/).
