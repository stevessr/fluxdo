/// 多 Discourse 媒体上传公共链路。
///
/// linux.do 保留社区现有的 4MB + `.xz` 媒体隧道；其他 Discourse 实例
/// 使用标准 /uploads.json 能力、站点下发的 max_attachment_size_kb 与
/// authorized_extensions，不把 linux.do 的私有绕过策略扩散到别的站点。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:path_provider/path_provider.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../config/discourse_instance_runtime.dart';
import '../../services/app_error_handler.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/media_transcoder/media_compressor.dart';
import '../../services/media_transcoder/media_transcoder.dart';
import '../../services/preloaded_data_service.dart';

/// 站点允许上传的扩展名 —— 从 preloaded siteSettings 的
/// `authorized_extensions`(staff 追加 `authorized_extensions_for_staff`)
/// 动态派生,与网页端 `lib/uploads.js` 的 authorizedExtensions 同口径:
/// 小写、剥空白与点、按 `|` 拆、滤掉带 `*` 的通配项。
/// linux.do 的音视频隧道不走这里；通用实例则使用该名单做前置校验。
///
/// 返回 null = 不设限(任一名单含 `*`,官方 authorizesAllExtensions
/// 同款判定;或 siteSettings 未加载 —— 此时让服务端裁决,好过拿一份
/// 写死的列表两头错:站点允许的选不了、列表里有的选完照样 422)。
List<String>? attachmentAllowedExtensions() {
  final preloaded = PreloadedDataService();
  final base = preloaded.siteSettingsSync?['authorized_extensions'] as String?;
  if (base == null) return null;
  final user = preloaded.currentUserSync;
  final isStaff = user?['admin'] == true || user?['moderator'] == true;
  final staffExtra = isStaff
      ? (preloaded.siteSettingsSync?['authorized_extensions_for_staff']
            as String?)
      : null;

  if (base.contains('*') || (staffExtra?.contains('*') ?? false)) {
    return null;
  }
  final exts = {
    ..._extensionsToList(base),
    if (staffExtra != null) ..._extensionsToList(staffExtra),
  }.toList();
  return exts.isEmpty ? null : exts;
}

List<String> _extensionsToList(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[\s.]+'), '')
    .split('|')
    .where((ext) => ext.isNotEmpty && !ext.contains('*'))
    .toList();

/// 从标准 Discourse site settings 读取附件体积上限。
///
/// 返回 null 表示设置尚未加载或站点没有提供可用限制，此时交给服务端裁决。
/// linux.do 在 preload 尚未完成时保留历史 4MiB 回退。
int? activeMediaUploadLimitBytes() {
  return mediaUploadLimitBytesFromSettings(
    PreloadedDataService().siteSettingsSync,
    fallbackBytes: DiscourseInstanceRuntime.isDefaultInstance
        ? kMaxMediaBytes
        : null,
  );
}

int? mediaUploadLimitBytesFromSettings(
  Map<String, dynamic>? settings, {
  int? fallbackBytes,
}) {
  final raw = settings?['max_attachment_size_kb'];
  final int? kb;
  if (raw is num) {
    kb = raw.toInt();
  } else if (raw is String) {
    kb = int.tryParse(raw.trim());
  } else {
    kb = null;
  }
  if (kb == null || kb <= 0) return fallbackBytes;
  return kb * 1024;
}

bool _extensionAllowedForGenericInstance(String filename) {
  final allowed = attachmentAllowedExtensions();
  if (allowed == null) return true;
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return false;
  return allowed.contains(filename.substring(dot + 1).toLowerCase());
}

String _formatUploadLimit(int bytes) {
  final mib = bytes / (1024 * 1024);
  if (mib >= 1) {
    final value = mib == mib.roundToDouble()
        ? mib.toInt().toString()
        : mib.toStringAsFixed(1);
    return '$value MB';
  }
  return '${(bytes / 1024).round()} KB';
}

/// `upload://<base62>.<ext>` → `/uploads/short-url/<base62>.xz` 播放路径。
String mediaShortUrlToXzPath(String shortUrl) {
  if (shortUrl.startsWith('upload://')) {
    final token = shortUrl.substring('upload://'.length);
    final dot = token.lastIndexOf('.');
    final stem = dot > 0 ? token.substring(0, dot) : token;
    return '/uploads/short-url/$stem.xz';
  }
  // 兜底:服务端未返回短链(直返 url)时仅换扩展
  final dot = shortUrl.lastIndexOf('.');
  return dot > 0 ? '${shortUrl.substring(0, dot)}.xz' : shortUrl;
}

/// 生成插入 raw 的媒体 HTML 标签。[voice] = 语音消息(包 `[wrap=voice]`
/// 壳,本 app 渲染语音条,网页端无样式影响)。
String buildMediaTag({
  required bool isAudio,
  required String srcPath,
  required String mime,
  bool voice = false,
}) {
  if (isAudio) {
    final tag =
        '<audio controls>\n  <source src="$srcPath" type="$mime">\n</audio>';
    return voice ? '[wrap=voice]\n$tag\n[/wrap]' : tag;
  }
  return '<video width="640" height="360" controls>\n'
      '  <source src="$srcPath" type="$mime">\n'
      '</video>';
}

/// 已有本地媒体文件 → 按当前实例能力压缩/上传 → 可插入正文的文本。
/// linux.do 生成历史媒体 HTML；通用 Discourse 使用标准 media markdown。
Future<String?> uploadMediaFileAsTag(
  BuildContext context, {
  required String path,
  required String name,
  required bool isAudio,
  bool voice = false,
}) async {
  try {
    var uploadPath = path;
    var uploadName = name;
    final size = await File(path).length();
    final maxBytes = activeMediaUploadLimitBytes();
    final exceedsLimit =
        maxBytes != null &&
        (DiscourseInstanceRuntime.isDefaultInstance
            ? size >= maxBytes
            : size > maxBytes);
    if (maxBytes != null && exceedsLimit) {
      if (!context.mounted) return null;
      final compressed = await compressMediaWithDialog(
        context,
        path: path,
        isAudio: isAudio,
        maxBytes: maxBytes,
      );
      if (compressed == null) return null;
      uploadPath = compressed;
      uploadName = compressed.split(Platform.pathSeparator).last;
    }

    final service = DiscourseService();
    if (!DiscourseInstanceRuntime.isDefaultInstance) {
      if (!_extensionAllowedForGenericInstance(uploadName)) {
        final dot = uploadName.lastIndexOf('.');
        final ext = dot >= 0 ? uploadName.substring(dot) : uploadName;
        throw Exception('当前 Discourse 不允许上传 $ext 文件');
      }
      final result = await service.uploadFile(uploadPath);
      // 标准 Discourse 会把 |audio / |video upload markdown cook 成媒体元素，
      // 不依赖 linux.do 的 xz 路由和自定义 raw HTML。
      return result.toAutoMarkdown(alt: name);
    }

    final mime = lookupMimeType(uploadName) ??
        (isAudio ? 'audio/mpeg' : 'video/mp4');
    final result = await service.uploadMediaAsXz(uploadPath);
    return buildMediaTag(
      isAudio: isAudio,
      srcPath: mediaShortUrlToXzPath(result.shortUrl),
      mime: mime,
      voice: voice,
    );
  } catch (e, s) {
    if (context.mounted) {
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : '媒体上传失败';
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(msg)));
    } else {
      AppErrorHandler.handleUnexpected(e, s);
    }
    return null;
  }
}

/// 选择音/视频文件并上传,返回标签文本;取消/失败返回 null。
Future<String?> pickAndUploadMediaTag(
  BuildContext context, {
  required bool isAudio,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: isAudio ? FileType.audio : FileType.video,
  );
  final file = picked?.files.single;
  final path = file?.path;
  if (file == null || path == null || !context.mounted) return null;
  return uploadMediaFileAsTag(
    context,
    path: path,
    name: file.name,
    isAudio: isAudio,
  );
}

/// 超限媒体压缩(模态进度对话框,可取消)。返回压缩后文件路径;
/// null = 取消 / 失败 / 平台不支持(失败已 SnackBar 提示)。
Future<String?> compressMediaWithDialog(
  BuildContext context, {
  required String path,
  required bool isAudio,
  int maxBytes = kMaxMediaBytes,
}) async {
  final transcoder = MediaTranscoder.forCurrentPlatform();
  if (transcoder == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '当前平台不支持压缩,请压到 \${_formatUploadLimit(maxBytes)} 内再上传',
        ),
      ),
    );
    return null;
  }
  final tempDir = await getTemporaryDirectory();
  if (!context.mounted) return null;

  final status = ValueNotifier<String>('准备压缩…');
  final resultFuture = compressMediaToFit(
    transcoder,
    path,
    isAudio: isAudio,
    outputDir: tempDir.path,
    maxBytes: maxBytes,
    onStatus: (s) => status.value = s,
  );

  final result = await showDialog<CompressResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => _CompressProgressDialog(
      transcoder: transcoder,
      status: status,
      resultFuture: resultFuture,
    ),
  );
  status.dispose();
  // 对话框被意外关闭(极端路径)也要等结果收尾
  final r = result ?? await resultFuture;
  if (r.isOk) return r.path;
  if (!r.cancelled && r.error != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(r.error!)));
  }
  return null;
}

class _CompressProgressDialog extends StatefulWidget {
  const _CompressProgressDialog({
    required this.transcoder,
    required this.status,
    required this.resultFuture,
  });

  final MediaTranscoder transcoder;
  final ValueNotifier<String> status;
  final Future<CompressResult> resultFuture;

  @override
  State<_CompressProgressDialog> createState() =>
      _CompressProgressDialogState();
}

class _CompressProgressDialogState extends State<_CompressProgressDialog> {
  Timer? _timer;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      final p = await widget.transcoder.progress();
      if (mounted) setState(() => _progress = p);
    });
    widget.resultFuture.then((r) {
      if (mounted) Navigator.of(context).pop(r);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('压缩媒体'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: widget.status,
            builder: (_, s, _) => Align(
              alignment: Alignment.centerLeft,
              child: Text(s, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          const SizedBox(height: 12),
          M3eLinearProgress(
            value: _progress <= 0 ? null : _progress.clamp(0.0, 1.0),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => widget.transcoder.cancel(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
