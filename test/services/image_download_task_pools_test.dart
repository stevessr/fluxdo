import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/download_request_queue.dart';
import 'package:fluxdo/services/image_download_task_pools.dart';

void main() {
  final mainImage = Uri.parse('https://linux.do/uploads/default/a.png');
  final mainAvatar = Uri.parse('https://avatars.linux.do/user_avatar/a.png');
  final cdnImage = Uri.parse('https://cdn.example.org/uploads/a.png');

  test('仅主站及合法子域使用专属任务池，第三方继续按内容分池', () {
    final pools = ImageDownloadTaskPools(mainHost: 'linux.do');
    final main = pools.queueFor(mainImage, DownloadChannel.content);
    expect(pools.queueFor(mainAvatar, DownloadChannel.content), same(main));
    expect(
      pools.queueFor(mainImage, DownloadChannel.small),
      isNot(same(main)),
    );
    expect(
      pools.queueFor(mainImage, DownloadChannel.sticker),
      isNot(same(main)),
    );
    expect(
      pools.queueFor(mainImage, DownloadChannel.small),
      isNot(same(pools.queueFor(cdnImage, DownloadChannel.small))),
    );
    expect(
      pools.queueFor(mainImage, DownloadChannel.sticker),
      isNot(same(pools.queueFor(cdnImage, DownloadChannel.sticker))),
    );
    expect(
      pools.isMainDomain(
        Uri.parse('https://linux.do.evil.example/uploads/a.png'),
      ),
      isFalse,
    );
    expect(
      pools.isMainDomain(Uri.parse('https://notlinux.do/uploads/a.png')),
      isFalse,
    );
    expect(
      pools.queueFor(cdnImage, DownloadChannel.content),
      isNot(same(main)),
    );
    expect(
      pools.queueFor(cdnImage, DownloadChannel.small),
      isNot(same(pools.queueFor(cdnImage, DownloadChannel.content))),
    );
    expect(
      pools.queueFor(cdnImage, DownloadChannel.sticker),
      isNot(same(pools.queueFor(cdnImage, DownloadChannel.content))),
    );
  });

  test('CDN 正文图片占满六槽时主站图片无需等待', () async {
    final pools = ImageDownloadTaskPools(mainHost: 'linux.do');
    final cdn = pools.queueFor(cdnImage, DownloadChannel.content);
    final main = pools.queueFor(mainImage, DownloadChannel.content);

    for (var i = 0; i < 6; i++) {
      await cdn.acquire('cdn-running-$i', DownloadPriority.normal);
    }
    var cdnPendingStarted = false;
    final pending = cdn
        .acquire('cdn-pending', DownloadPriority.normal)
        .then((_) => cdnPendingStarted = true);

    await main
        .acquire('main-image', DownloadPriority.normal)
        .timeout(const Duration(seconds: 1));
    expect(cdnPendingStarted, isFalse);
    main.release();

    cdn.release();
    await pending.timeout(const Duration(seconds: 1));
    expect(cdnPendingStarted, isTrue);
    for (var i = 0; i < 6; i++) {
      cdn.release();
    }
  });

  test('主站占满八槽时 CDN 图片仍可进入自己的任务池', () async {
    final pools = ImageDownloadTaskPools(mainHost: 'linux.do');
    final main = pools.queueFor(mainImage, DownloadChannel.content);
    final cdn = pools.queueFor(cdnImage, DownloadChannel.content);

    for (var i = 0; i < 8; i++) {
      await main.acquire('main-running-$i', DownloadPriority.normal);
    }
    var mainPendingStarted = false;
    final pending = main
        .acquire('main-pending', DownloadPriority.normal)
        .then((_) => mainPendingStarted = true);

    await cdn
        .acquire('cdn-image', DownloadPriority.normal)
        .timeout(const Duration(seconds: 1));
    expect(mainPendingStarted, isFalse);
    cdn.release();

    main.release();
    await pending.timeout(const Duration(seconds: 1));
    expect(mainPendingStarted, isTrue);
    for (var i = 0; i < 8; i++) {
      main.release();
    }
  });

  test('主站贴纸正在批量下载时不阻塞主站正文图片', () async {
    final pools = ImageDownloadTaskPools(mainHost: 'linux.do');
    final sticker = pools.queueFor(mainImage, DownloadChannel.sticker);
    final content = pools.queueFor(mainImage, DownloadChannel.content);

    await sticker.acquire('sticker-a', DownloadPriority.normal);
    await sticker.acquire('sticker-b', DownloadPriority.normal);
    await sticker.acquire('sticker-c', DownloadPriority.high);
    var stickerPendingStarted = false;
    final pending = sticker
        .acquire('sticker-pending', DownloadPriority.normal)
        .then((_) => stickerPendingStarted = true);

    await content
        .acquire('main-content', DownloadPriority.high)
        .timeout(const Duration(seconds: 1));
    expect(stickerPendingStarted, isFalse);
    content.release();

    sticker.release();
    sticker.release();
    await pending.timeout(const Duration(seconds: 1));
    for (var i = 0; i < 2; i++) {
      sticker.release();
    }
  });

  test('主站视口提权作用于主站池而不是 CDN 内容池', () async {
    final pools = ImageDownloadTaskPools(mainHost: 'linux.do');
    final main = pools.queueFor(mainImage, DownloadChannel.content);
    for (var i = 0; i < 8; i++) {
      await main.acquire('running-$i', DownloadPriority.normal);
    }
    final order = <String>[];
    final first = main
        .acquire('https://linux.do/uploads/first.png', DownloadPriority.normal)
        .then((_) => order.add('first'));
    final secondUrl = 'https://linux.do/uploads/second.png';
    final second = main
        .acquire(secondUrl, DownloadPriority.normal)
        .then((_) => order.add('second'));

    pools.bumpPending(DownloadChannel.content, secondUrl);
    main.release();
    await second.timeout(const Duration(seconds: 1));
    expect(order, ['second']);

    main.release();
    await first.timeout(const Duration(seconds: 1));
    expect(order, ['second', 'first']);
    for (var i = 0; i < 8; i++) {
      main.release();
    }
  });
}
