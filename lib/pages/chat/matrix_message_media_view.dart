import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../services/matrix_client_service.dart';
import '../../services/messaging/matrix_media_service.dart';

class MatrixMessageMediaView extends StatefulWidget {
  const MatrixMessageMediaView({
    super.key,
    required this.message,
    required this.session,
  });

  final MatrixMessage message;
  final MatrixSession session;

  @override
  State<MatrixMessageMediaView> createState() => _MatrixMessageMediaViewState();
}

class _MatrixMessageMediaViewState extends State<MatrixMessageMediaView> {
  late MatrixMediaService _media;
  Future<Uint8List>? _thumbnailFuture;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant MatrixMessageMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.accessToken != widget.session.accessToken ||
        oldWidget.session.homeserver != widget.session.homeserver ||
        oldWidget.message.mediaUri != widget.message.mediaUri ||
        oldWidget.message.thumbnailUri != widget.message.thumbnailUri) {
      _configure();
    }
  }

  void _configure() {
    _media = MatrixMediaService(session: widget.session);
    _error = null;
    _thumbnailFuture = widget.message.isImage && widget.message.mediaUri != null
        ? _loadThumbnail()
        : null;
  }

  Future<Uint8List> _loadThumbnail() {
    final thumbnail = widget.message.thumbnailUri;
    if (thumbnail != null) {
      return _media.downloadBytes(
        thumbnail,
        maxBytes: MatrixMediaService.defaultThumbnailLimitBytes,
      );
    }
    return _media.downloadThumbnailBytes(widget.message.mediaUri!);
  }

  Future<void> _openMedia() async {
    final uri = widget.message.mediaUri;
    if (uri == null || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (widget.message.isImage) {
        final bytes = await _media.downloadBytes(uri);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
        return;
      }

      if (kIsWeb) {
        throw const MatrixMediaException(
          'Web 端暂不支持把带认证头的 Matrix 附件交给系统打开。',
        );
      }
      final bytes = await _media.downloadBytes(uri);
      final temp = await getTemporaryDirectory();
      final safeName = _safeFilename(widget.message.filename ?? widget.message.body);
      final path = p.join(temp.path, 'fluxdo-matrix-${widget.message.eventId.hashCode}-$safeName');
      final file = XFile.fromData(bytes, name: safeName);
      await file.saveTo(path);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && result.type != ResultType.noAppToOpen) {
        throw MatrixMediaException(result.message);
      }
      if (result.type == ResultType.noAppToOpen) {
        throw const MatrixMediaException('系统中没有可以打开该附件的应用。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  static String _safeFilename(String value) {
    final base = p.basename(value.trim());
    final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'attachment'
        : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.message.hasMedia || widget.message.mediaUri == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final meta = <String>[
      if (widget.message.mimeType?.isNotEmpty == true) widget.message.mimeType!,
      if (widget.message.mediaSize != null) _formatBytes(widget.message.mediaSize!),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.message.isImage)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder<Uint8List>(
                  future: _thumbnailFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return InkWell(
                        onTap: _opening ? null : _openMedia,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return _MediaPlaceholder(
                        icon: Icons.broken_image_outlined,
                        label: '缩略图加载失败，点击重试',
                        onTap: () {
                          setState(() => _thumbnailFuture = _loadThumbnail());
                        },
                      );
                    }
                    return const SizedBox(
                      width: 220,
                      height: 140,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              ),
            )
          else
            Material(
              color: colors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _opening ? null : _openMedia,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(_iconForMime(widget.message.mimeType), size: 28),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.message.filename ?? widget.message.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (meta.isNotEmpty)
                              Text(meta, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_opening)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.open_in_new_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.message.isImage && meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(meta, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconForMime(String? mime) {
    final value = mime?.toLowerCase() ?? '';
    if (value.startsWith('audio/')) return Icons.audio_file_outlined;
    if (value.startsWith('video/')) return Icons.video_file_outlined;
    if (value == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (value.startsWith('text/')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
    return '${(mib / 1024).toStringAsFixed(1)} GiB';
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 220,
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 30),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
