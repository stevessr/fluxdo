import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_icons/app_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/s.dart';
import '../services/qr_login_service.dart';
import '../services/pico_vr_service.dart';
import '../services/toast_service.dart';

import 'package:m3e_ui/m3e_ui.dart';

/// 待登录设备:扫描另一台已登录设备展示的登录二维码。
///
/// - Android / iOS / macOS:优先实时相机([mobile_scanner])
/// - Linux / Windows / 无相机:从相册选图,用 zxing2 解码
class QrLoginScanPage extends StatefulWidget {
  const QrLoginScanPage({super.key});

  @override
  State<QrLoginScanPage> createState() => _QrLoginScanPageState();
}

class _QrLoginScanPageState extends State<QrLoginScanPage> {
  MobileScannerController? _controller;
  bool _handling = false;
  bool _cameraSupported = false;
  bool _systemCameraAvailable = false;
  bool _externalQrScannerAvailable = false;
  bool _checkingCamera = false;
  bool _pickingImage = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    // Unlike phones, many XR headsets expose no camera through Android
    // Camera2 even when they have physical passthrough cameras. Do not start
    // CameraX/mobile_scanner on an unenumerated camera.
    if (!kIsWeb && Platform.isAndroid) {
      _checkingCamera = true;
      unawaited(_initializeAndroidCamera());
    } else {
      _cameraSupported = _isCameraPlatform;
      if (_cameraSupported) _initializeScanner();
    }
  }

  void _initializeScanner() {
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: true,
    );
  }

  Future<void> _initializeAndroidCamera() async {
    final caps = await PicoVrService.instance.capabilities;
    if (!mounted) return;
    setState(() {
      _checkingCamera = false;
      _cameraSupported = caps.canUseMobileScanner;
      _systemCameraAvailable = caps.hasCameraCaptureIntent;
      _externalQrScannerAvailable = caps.hasExternalQrScanner;
      if (_cameraSupported) _initializeScanner();
    });
  }

  Future<void> _pasteQrContent() async {
    if (_handling || _pickingImage) return;
    try {
      final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      if (!mounted) return;
      if (raw == null || QrLoginService.instance.parsePayload(raw) == null) {
        ToastService.showError(S.current.login_qrScanFailed);
        return;
      }
      await _completeWithRaw(raw);
    } catch (e) {
      debugPrint('[QrLoginScan] Clipboard import failed: $e');
      if (mounted) ToastService.showError(S.current.login_qrScanFailed);
    }
  }

  String get _systemCameraLabel =>
      Localizations.localeOf(context).languageCode == 'zh'
          ? '系统相机拍摄二维码'
          : 'Capture QR with system camera';

  String get _externalQrLabel =>
      Localizations.localeOf(context).languageCode == 'zh'
          ? '使用系统扫码应用'
          : 'Scan with another app';

  String get _pasteLabel =>
      Localizations.localeOf(context).languageCode == 'zh'
          ? '粘贴二维码内容'
          : 'Paste QR content';

  bool get _isCameraPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _pickingImage) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    // 先快速过滤非本协议内容,避免误扫普通二维码就弹错误
    if (QrLoginService.instance.parsePayload(raw) == null) return;
    await _completeWithRaw(raw);
  }

  Future<void> _scanWithExternalQrScanner() async {
    if (_handling || _pickingImage) return;
    // A third-party scanner receives the plaintext QR payload, including
    // the API key (which may not expire) and one-time login OTP.
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(zh ? '外部扫码安全提醒' : 'External scanner security'),
        content: Text(zh
            ? '登录二维码包含明文 API Key 和一次性验证码，API Key 可能长期有效。'
              '外部扫码应用能够读取这些凭证。请仅在信任该应用时继续，'
              '否则使用应用内相机、图片导入或粘贴。'
            : 'Login QR codes contain a plaintext API key and one-time '
              'code. The API key may not expire. External scanner apps can '
              'read these credentials. Continue only if you trust the app, '
              'or use the in-app camera, image import or paste.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(zh ? '继续扫码' : 'Continue'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() => _pickingImage = true);
    try {
      final raw = await PicoVrService.instance.scanWithExternalQrScanner();
      if (!mounted || raw == null) return;
      final text = raw.trim();
      if (QrLoginService.instance.parsePayload(text) == null) {
        ToastService.showError(S.current.login_qrScanFailed);
        return;
      }
      await _completeWithRaw(text);
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _pickFromGallery() => _pickImage(ImageSource.gallery);

  /// A vendor camera activity may exist even when Camera2 is unavailable.
  /// Camera capture intents do not provide access to XR passthrough frames.
  Future<void> _captureWithSystemCamera() => _pickImage(ImageSource.camera);

  Future<void> _pickImage(ImageSource source) async {
    if (_handling || _pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final file = await ImagePicker().pickImage(source: source);
      if (file == null || !mounted) return;
      setState(() => _statusMessage = S.current.login_qrDecodingImage);
      final bytes = await file.readAsBytes();
      final raw = await QrLoginService.instance.decodeQrFromImageBytes(bytes);
      if (!mounted) return;
      if (raw == null || raw.isEmpty) {
        ToastService.showError(S.current.login_qrNoCodeInImage);
        setState(() => _statusMessage = null);
        return;
      }
      await _completeWithRaw(raw);
    } catch (e) {
      debugPrint('[QrLoginScan] 图片选择/拍摄失败: $e');
      if (mounted) {
        ToastService.showError(S.current.login_qrScanFailed);
        setState(() => _statusMessage = null);
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _completeWithRaw(String raw) async {
    if (_handling) return;
    setState(() {
      _handling = true;
      _statusMessage = S.current.login_qrLoggingIn;
    });
    // 暂停相机,避免重复触发
    try {
      await _controller?.stop();
    } catch (_) {}

    try {
      await QrLoginService.instance.loginWithScannedContent(raw);
      if (!mounted) return;
      ToastService.showSuccess(S.current.login_qrSuccess);
      Navigator.of(context).pop(true);
    } on QrLoginException catch (e) {
      if (!mounted) return;
      ToastService.showError(e.message);
      setState(() {
        _handling = false;
        _statusMessage = null;
      });
      try {
        await _controller?.start();
      } catch (_) {}
    } catch (e) {
      debugPrint('[QrLoginScan] 登录失败: $e');
      if (!mounted) return;
      ToastService.showError(S.current.login_qrScanFailed);
      setState(() {
        _handling = false;
        _statusMessage = null;
      });
      try {
        await _controller?.start();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.login_qrScanTitle),
        actions: [
          if (_cameraSupported)
            IconButton(
              tooltip: context.l10n.login_qrPickImage,
              onPressed: _handling || _pickingImage ? null : _pickFromGallery,
              icon: const Icon(Symbols.photo_library_rounded),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_checkingCamera)
            const Center(child: CircularProgressIndicator())
          else if (_cameraSupported && _controller != null)
            _buildCameraBody(theme, scheme)
          else
            _buildGalleryOnlyBody(theme, scheme),
          if (_handling || _statusMessage != null)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LoadingSpinner(),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraBody(ThemeData theme, ColorScheme scheme) {
    return Column(
      children: [
        Expanded(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller!,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) {
                    return _CameraErrorPane(
                      message: error.errorDetails?.message ?? error.toString(),
                      onPickImage: _pickFromGallery,
                      onCapture: _systemCameraAvailable
                          ? _captureWithSystemCamera
                          : null,
                      onPaste: _pasteQrContent,
                      onExternalScan: _externalQrScannerAvailable
                          ? _scanWithExternalQrScanner
                          : null,
                      externalScanLabel: _externalQrLabel,
                      captureLabel: _systemCameraLabel,
                      pasteLabel: _pasteLabel,
                    );
                  },
                ),
                // 简易取景框提示
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Text(
                  context.l10n.login_qrScanHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _handling || _pickingImage ? null : _pickFromGallery,
                  icon: const Icon(Symbols.photo_library_rounded, size: 20),
                  label: Text(context.l10n.login_qrPickImage),
                ),
                if (_externalQrScannerAvailable) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _handling || _pickingImage
                        ? null
                        : _scanWithExternalQrScanner,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    label: Text(_externalQrLabel),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _handling || _pickingImage ? null : _pasteQrContent,
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  label: Text(_pasteLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryOnlyBody(ThemeData theme, ColorScheme scheme) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.qr_code_scanner_rounded,
                size: 72,
                color: scheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                context.l10n.login_qrGalleryOnlyHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _handling || _pickingImage ? null : _pickFromGallery,
                icon: const Icon(Symbols.photo_library_rounded),
                label: Text(context.l10n.login_qrPickImage),
                style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
              ),
              if (_externalQrScannerAvailable) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _handling || _pickingImage
                      ? null
                      : _scanWithExternalQrScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(_externalQrLabel),
                ),
              ],
              if (_systemCameraAvailable) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _handling || _pickingImage
                      ? null
                      : _captureWithSystemCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(_systemCameraLabel),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _handling || _pickingImage ? null : _pasteQrContent,
                icon: const Icon(Icons.content_paste_rounded),
                label: Text(_pasteLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraErrorPane extends StatelessWidget {
  const _CameraErrorPane({
    required this.message,
    required this.onPickImage,
    required this.onPaste,
    required this.externalScanLabel,
    this.onExternalScan,
    required this.captureLabel,
    required this.pasteLabel,
    this.onCapture,
  });

  final String message;
  final VoidCallback onPickImage;
  final VoidCallback onPaste;
  final VoidCallback? onExternalScan;
  final String externalScanLabel;
  final VoidCallback? onCapture;
  final String captureLabel;
  final String pasteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Symbols.no_photography_rounded,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.login_qrCameraUnavailable,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onPickImage,
                icon: const Icon(Symbols.photo_library_rounded),
                label: Text(context.l10n.login_qrPickImage),
              ),
              if (onExternalScan != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onExternalScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(externalScanLabel),
                ),
              ],
              if (onCapture != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onCapture,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(captureLabel),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_rounded),
                label: Text(pasteLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
