import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main.dart' as cfluxdo;
import 'pages/cdk/cdk_home_page.dart';
import 'pages/ld_store/ld_store_home_page.dart';
import 'pages/login_page.dart';
import 'providers/core_providers.dart';
import 'services/local_notification_service.dart' show navigatorKey;

/// 外部 APK 复用 CFluxDo 的原生页面、授权与网络依赖。
///
/// 注意：不同 applicationId 之间不共享论坛 Cookie、用户资料或凭据。
/// 通过已存在的 CFluxDo 启动流程初始化这些依赖，再将根路由替换成插件入口。
enum CommunityPluginKind { cdk, ldShop }

Future<void> startCommunityPlugin(
  List<String> args,
  CommunityPluginKind kind,
) async {
  // 保持 CFluxDo 原生的站点/账号/本地化/OAuth 初始化逻辑。
  await cfluxdo.main(args);

  var attempts = 0;
  void openWhenReady(Duration _) {
    final navigator = navigatorKey.currentState;
    if (navigator != null && navigator.mounted) {
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/plugin/${kind.name}'),
          builder: (_) => _PluginRoot(kind: kind),
        ),
        (_) => false,
      );
    } else if (++attempts < 30) {
      WidgetsBinding.instance.addPostFrameCallback(openWhenReady);
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  WidgetsBinding.instance.addPostFrameCallback(openWhenReady);
  WidgetsBinding.instance.ensureVisualUpdate();
}

class _PluginRoot extends ConsumerWidget {
  const _PluginRoot({required this.kind});

  final CommunityPluginKind kind;

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
    // 从登录流程返回后重新查询论坛会话，让 CDK/商城识别当前用户。
    if (context.mounted) ref.invalidate(currentUserProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(currentUserProvider);
    final loggedIn = userState.value != null;

    if (kind == CommunityPluginKind.ldShop) {
      // 商品列表/分类/搜索匿名可用；订单、优惠券、结算由上游原生页处理。
      // 未登录时可在商城内显式使用论坛登录，不共享宿主应用凭据。
      return Stack(
        children: [
          const LdStoreHomePage(),
          if (!loggedIn)
            Positioned(
              right: 16,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
              child: FloatingActionButton.extended(
                heroTag: 'ldshop-plugin-login',
                onPressed: () => _login(context, ref),
                icon: const Icon(Icons.login_rounded),
                label: const Text('登录 LINUX DO'),
              ),
            ),
        ],
      );
    }

    if (userState.isLoading && !userState.hasValue) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (loggedIn) return const CdkHomePage();

    return Scaffold(
      appBar: AppBar(title: const Text('LINUX DO CDK')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.redeem_rounded, size: 56),
              const SizedBox(height: 16),
              const Text(
                '请先在此插件中登录 LINUX DO，再授权 CDK。'
                '插件与 Fluxdo 主程序的登录状态彼此隔离。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _login(context, ref),
                icon: const Icon(Icons.login_rounded),
                label: const Text('登录 LINUX DO'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(currentUserProvider),
                child: const Text('重新检查登录状态'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
