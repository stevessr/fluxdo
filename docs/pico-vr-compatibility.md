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
The PICO SDK 3.4.0 `PXR_CameraImage` / `XR_PICO_camera_image` API works
with a supported XR session; that is not provided by a normal Flutter 2D panel.

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
- **Not implemented**: live scanning through PICO XR passthrough (requires a
  dedicated native OpenXR or official PICO SDK integration and permissions).
  The PICO Unity Integration SDK 3.4.0 release introduced camera image APIs,
  but Flutter's normal 2D Activity does not create the required XR session.
  A native XR scanning flow must be independently built and verified on the
  headset; Android Camera2 workarounds cannot substitute for it.

### External scanner interoperability

- Uses the publicly documented ZXing scan action, restricted to `QR_CODE`.
  Only apps registered for the action are offered; PICO system-private
  activities are not hardcoded.
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
