import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../services/system_browser_service.dart';
import '../../utils/svg_utils.dart';

/// 可独立测试的浏览器选择弹窗。系统「打开方式」始终在滚动列表外，
/// 防止浏览器安装数量多时入口被挤到列表末尾。
class LoginBrowserPickerSheet extends StatelessWidget {
  const LoginBrowserPickerSheet({super.key, required this.browsers});

  final List<LoginBrowser> browsers;

  Widget _browserIcon(LoginBrowser browser) {
    final bytes = browser.iconBytes;
    if (bytes == null || bytes.isEmpty) {
      return const Icon(Icons.open_in_browser_rounded, size: 28);
    }
    if (browser.iconIsSvg) {
      try {
        final source = SvgUtils.stripActiveContent(utf8.decode(bytes));
        final image = ScalableImage.fromSvgString(
          SvgUtils.sanitize(source),
          warnF: (_) {},
        );
        return SizedBox(
          width: 40,
          height: 40,
          child: ScalableImageWidget(si: image, fit: BoxFit.contain),
        );
      } catch (_) {
        return const Icon(Icons.open_in_browser_rounded, size: 28);
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.memory(
        bytes,
        width: 40,
        height: 40,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.open_in_browser_rounded, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chooser = browsers
        .where((browser) => browser.id == SystemBrowserService.androidChooserId)
        .toList(growable: false);
    final direct = browsers
        .where((browser) => browser.id != SystemBrowserService.androidChooserId)
        .toList(growable: false);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选择浏览器', style: Theme.of(context).textTheme.titleLarge),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Text(
                '选择已登录 Google / GitHub 等账号的浏览器，'
                '在 LINUX DO 完成授权后将自动返回 FluxDO。',
                textAlign: TextAlign.center,
              ),
            ),
            if (direct.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: direct.length,
                  itemBuilder: (tileContext, index) {
                    final browser = direct[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: _browserIcon(browser)),
                      ),
                      title: Text(
                        browser.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(tileContext).pop(browser),
                    );
                  },
                ),
              )
            else if (chooser.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('没有找到可直接选择的浏览器，可尝试系统打开方式。'),
              ),
            if (chooser.isNotEmpty) ...[
              const Divider(height: 12, indent: 16, endIndent: 16),
              ListTile(
                leading: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.apps_rounded, size: 28),
                ),
                title: Text(chooser.first.name),
                subtitle: const Text('唤起 Android 系统的“打开方式”菜单'),
                onTap: () => Navigator.of(context).pop(chooser.first),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
