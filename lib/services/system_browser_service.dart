import 'dart:io';

import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import 'desktop_browser_discovery.dart';
export 'desktop_browser_discovery.dart' show LoginBrowser;

/// Opens Discourse's User API Key authorization page in a particular installed
/// browser, so an existing Google/GitHub login in that browser can be reused.
///
/// The provider's OAuth callback still goes to linux.do. The separate
/// discourse://auth_redirect callback is handled by DeepLinkService.
class SystemBrowserService {
  SystemBrowserService._();
  static final instance = SystemBrowserService._();

  static const _channel = MethodChannel('com.github.lingyan000.fluxdo/browser');
  static const _default = LoginBrowser(id: 'default', name: '系统默认浏览器');
  static const androidChooserId = 'android:chooser';
  static const _androidChooser = LoginBrowser(
    id: androidChooserId,
    name: '使用系统方式打开',
  );

  // Flatpak must not inspect or execute binaries on the host. The portal's
  // OpenURI ask option displays the host's browser/application chooser.
  static const _portalChooser = LoginBrowser(
    id: 'portal:chooser',
    name: '选择系统已安装的浏览器',
  );

  static bool get _inFlatpak =>
      Platform.environment.containsKey('FLATPAK_ID') ||
      File('/.flatpak-info').existsSync();

  static const linuxBrowserCommands =
      DesktopBrowserDiscovery.linuxBrowserCommands;
  static const macBrowserAppNames = DesktopBrowserDiscovery.macBrowserAppNames;
  static const windowsBrowserInstallPaths =
      DesktopBrowserDiscovery.windowsBrowserInstallPaths;

  /// Only use this launcher for our own HTTPS authorization endpoint.
  static bool isAuthorizationUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'linux.do' &&
      uri.path == '/user-api-key/new';

  /// 把 Android PackageManager 枚举结果转换为可渲染的条目。
  /// 系统选择器始终置底，即便包名发现受系统限制也仍可使用。
  static List<LoginBrowser> decodeAndroidBrowsers(List<dynamic>? raw) {
    final browsers = <LoginBrowser>[];
    for (final entry in raw ?? const <dynamic>[]) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final name = entry['name'];
      if (id is! String || name is! String || id.isEmpty ||
          id == androidChooserId) {
        continue;
      }
      final icon = entry['icon'];
      browsers.add(LoginBrowser(
        id: id,
        name: name,
        iconBytes: icon is Uint8List && icon.isNotEmpty ? icon : null,
      ));
    }
    return [...browsers, _androidChooser];
  }

  Future<List<LoginBrowser>> availableBrowsers() async {
    if (Platform.isAndroid) {
      final raw = await _channel.invokeListMethod<dynamic>('listLoginBrowsers');
      return decodeAndroidBrowsers(raw);
    }

    if (Platform.isIOS) {
      final browsers = <LoginBrowser>[_default];
      for (final entry in const [
        (id: 'ios:chrome', name: 'Google Chrome', scheme: 'googlechromes'),
        (id: 'ios:firefox', name: 'Firefox', scheme: 'firefox'),
        (
          id: 'ios:edge',
          name: 'Microsoft Edge',
          scheme: 'microsoft-edge-https',
        ),
      ]) {
        if (await canLaunchUrl(Uri.parse('${entry.scheme}://open-url'))) {
          browsers.add(LoginBrowser(id: entry.id, name: entry.name));
        }
      }
      return browsers;
    }

    return DesktopBrowserDiscovery(
      platform: Platform.operatingSystem,
      environment: Platform.environment,
      inFlatpak: Platform.isLinux && _inFlatpak,
    ).availableBrowsers();
  }

  Future<bool> open(LoginBrowser browser, Uri authorizationUrl) async {
    if (!isAuthorizationUrl(authorizationUrl)) return false;
    try {
      if (browser.id == _portalChooser.id && Platform.isLinux && _inFlatpak) {
        return await _openWithPortalChooser(authorizationUrl);
      }
      if (browser.id == androidChooserId && Platform.isAndroid) {
        // Android ACTION_CHOOSER: 强制显示系统原生打开方式，而非直接使用默认浏览器。
        return await _channel.invokeMethod<bool>('launchLoginBrowserChooser', {
              'url': authorizationUrl.toString(),
            }) ??
            false;
      }
      if (browser.id == 'default') {
        return await launchUrl(
          authorizationUrl,
          mode: LaunchMode.externalApplication,
        );
      }
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('launchLoginBrowser', {
              'id': browser.id,
              'url': authorizationUrl.toString(),
            }) ??
            false;
      }
      if (Platform.isIOS) {
        late final Uri target;
        switch (browser.id) {
          case 'ios:chrome':
            target = authorizationUrl.replace(scheme: 'googlechromes');
            break;
          case 'ios:firefox':
            target = Uri.parse('firefox://open-url')
                .replace(queryParameters: {'url': authorizationUrl.toString()});
            break;
          case 'ios:edge':
            target = authorizationUrl.replace(scheme: 'microsoft-edge-https');
            break;
          default:
            return false;
        }
        return await launchUrl(target, mode: LaunchMode.externalApplication);
      }
      if (browser.executable == null) return false;
      if (browser.id.startsWith('xdg:')) {
        // GIO 提交启动请求后返回；检查退出码，避免把拒绝启动当作成功。
        return (await Process.run(browser.executable!, [
              ...browser.arguments,
              authorizationUrl.toString(),
            ])).exitCode ==
            0;
      }
      await Process.start(browser.executable!, [
        ...browser.arguments,
        authorizationUrl.toString(),
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// XDG Desktop Portal OpenURI v3+ with ask=true. This delegates selection
  /// to the host's trusted app chooser without sandbox escape permissions.
  /// GDBus returns a Request handle immediately; the eventual user choice,
  /// including cancellation, is handled asynchronously by the portal.
  Future<bool> _openWithPortalChooser(Uri uri) async {
    try {
      final result = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.portal.Desktop',
        '--object-path',
        '/org/freedesktop/portal/desktop',
        '--method',
        'org.freedesktop.portal.OpenURI.OpenURI',
        '',
        uri.toString(),
        "{'ask': <true>}",
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
