# PICO VR (PICO 4 Ultra) Android panel compatibility

Fluxdo remains a standard Flutter/Android **2D application** on PICO headsets.
It does not request an immersive XR session.

## Multiple windows

- `MainActivity` remains `singleTask` for OAuth and deep-link callbacks.
- A non-exported, resizeable `PicoVrWindowActivity` is launched with
  `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_MULTIPLE_TASK | FLAG_ACTIVITY_LAUNCH_ADJACENT`
  when users select **Settings → PICO VR · New window**. This is a real
  independent Android task; it requests native adjacent placement where the
  PICO shell supports it, rather than drawing a fake window inside Flutter.
- In Android landscape, the **topic overflow menu → Open in new window**
  carries the current topic and optional post number in Activity extras.
  The new Flutter engine consumes its own one-shot launch request after the
  onboarding/preheat gate and opens that topic. Nothing is stored in shared
  preferences or a global queue that could mix concurrent windows.
- In a PICO landscape panel, parallel view exposes a horizontal **tab strip**
  for currently open topic/profile/settings panes. Select a tab to move it
  to the foreground without deleting the others; close only the chosen tab.
  This strip is intra-window navigation, *not* an additional Android task.
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
- **Not implemented**: live scanning through PICO XR passthrough (requires a
  dedicated native OpenXR or official PICO SDK integration and permissions).

## Manual device matrix

1. On PICO 4 Ultra, confirm Settings shows **PICO VR · New window**.
   Open it twice; check each window navigates independently. Attempt a fourth
   secondary window and confirm the cap does not spawn an extra engine.
   Check Android's task overview, as well as PICO's panel switcher; do not
   accept two simulated Flutter panes as proof of native multi-window.
2. In landscape, open a topic overflow menu and choose **Open in new window**.
   Confirm the second Android task opens that exact topic/post; open two
   different topics in quick succession and confirm the requests do not cross.
   If the PICO shell declines adjacent placement, record the task/window
   behavior rather than claiming the panel was created.
3. In landscape parallel view, open several topics/profiles. Use the tab strip
   to revisit an earlier pane without discarding other tabs, close a
   background tab, and then close the active tab. Confirm embedded state and
   scrolling still belong to the original pane instances.
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
