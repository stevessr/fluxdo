import 'download_request_queue.dart';

/// 图片下载的并发通道。主站和第三方资源分别持有自己的任务池。
enum DownloadChannel {
  /// KB 级小文件（例如 emoji）。
  small,

  /// 正文图片、头像、原图和外部图片。
  content,

  /// 可能批量预取的大型贴纸原文件。
  sticker,
}

/// URL 域名与内容类型共同决定下载池，避免 CDN 大图/贴纸阻塞主站图片。
///
/// 主站（含子域）独享 small(12)/content(8)/sticker(3) 三个池，
/// 保留两级优先级和同级 FIFO；第三方资源继续使用原有
/// small(12)/content(6)/sticker(3) 三通道，不改变缓存与下载身份。
/// 这里限制的是完整响应体的下载数，而不只是建立连接的数量。
class ImageDownloadTaskPools {
  ImageDownloadTaskPools({required String mainHost})
      : _mainHost = mainHost.toLowerCase();

  final String _mainHost;

  final DownloadRequestQueue _mainSmall = DownloadRequestQueue(12);
  final DownloadRequestQueue _mainContent = DownloadRequestQueue(8);
  final DownloadRequestQueue _mainSticker = DownloadRequestQueue(
    3,
    reservedHighSlots: 1,
  );
  final DownloadRequestQueue _small = DownloadRequestQueue(12);
  final DownloadRequestQueue _content = DownloadRequestQueue(6);
  final DownloadRequestQueue _sticker = DownloadRequestQueue(
    3,
    reservedHighSlots: 1,
  );

  bool isMainDomain(Uri url) {
    final host = url.host.toLowerCase();
    return host.isNotEmpty &&
        _mainHost.isNotEmpty &&
        (host == _mainHost || host.endsWith('.$_mainHost'));
  }

  DownloadRequestQueue queueFor(Uri url, DownloadChannel channel) {
    if (isMainDomain(url)) {
      return switch (channel) {
        DownloadChannel.small => _mainSmall,
        DownloadChannel.content => _mainContent,
        DownloadChannel.sticker => _mainSticker,
      };
    }
    return switch (channel) {
      DownloadChannel.small => _small,
      DownloadChannel.content => _content,
      DownloadChannel.sticker => _sticker,
    };
  }

  /// 与 acquire 使用相同的 URL 路由，确保滚动提权不会误操作 CDN 池。
  void bumpPending(DownloadChannel channel, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    queueFor(uri, channel).bump(url);
  }

  /// 把滚出视口的排队图片移到其实际所在池的普通队列末尾。
  void sinkPending(DownloadChannel channel, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    queueFor(uri, channel).sink(url);
  }
}
