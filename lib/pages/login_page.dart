import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/s.dart';
import '../services/account_manager.dart';
import '../services/credential_store_service.dart';
import '../services/discourse/discourse_service.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';
import '../services/user_api_key_login_flow.dart';
import '../utils/blur_config.dart';
import '../widgets/auth/webview_login_dialog.dart';
import '../widgets/auth/login_form.dart';
import '../widgets/auth/two_factor_dialog.dart';
import '../widgets/common/ambient_background.dart';
import '../widgets/common/floating_logo.dart';

import 'package:m3e_ui/m3e_ui.dart';

import 'qr_login_scan_page.dart';
import 'webview_login_page.dart';

/// linux.do 原生登录页。
///
/// 主路径在轻量 WebView 内直接调用 Discourse JSON 登录接口，不加载完整 Ember
/// bundle，绕开低版本 WebView 对现代前端语法的兼容问题。
///
/// 登录能力按服务端响应自适应：默认先尝试无验证码登录；只有站点实际要求时
/// 才展示 hCaptcha。二步验证直接支持 TOTP 与备用码，安全密钥 / Passkey 等
/// WebAuthn 场景继续交给 [WebViewLoginPage]。
///
/// linux.do 的 hcaptcha sitekey 写死, 后续可从 PreloadedDataService 动态拿。
const String _kLinuxDoHcaptchaSiteKey = 'a776b4ac-8c4c-441e-986a-c6ee9ed8cf08';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  String? _savedUsername;
  String? _savedPassword;
  List<SavedLoginCredential> _savedCredentials = const [];
  bool _credentialsLoaded = false;
  bool _browserAuthLaunching = false;

  late final AnimationController _entryController;
  final List<Animation<double>> _fade = [];
  final List<Animation<Offset>> _slide = [];

  @override
  void initState() {
    super.initState();
    _setupEntryAnimations();
    _loadSavedCredentials();
  }

  /// staggered 入场动画 (对齐 onboarding 的节奏)
  void _setupEntryAnimations() {
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    for (var i = 0; i < 5; i++) {
      final start = i * 0.12;
      final end = (start + 0.6).clamp(0.0, 1.0);
      _fade.add(
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: Interval(start, end, curve: Curves.easeOut),
          ),
        ),
      );
      _slide.add(
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
    _entryController.forward();
  }

  @override
  void dispose() {
    if (identical(
      UserApiKeyLoginFlow.instance.onFlowFinished,
      _onBrowserAuthFinished,
    )) {
      UserApiKeyLoginFlow.instance.onFlowFinished = null;
    }
    _entryController.dispose();
    super.dispose();
  }

  /// 浏览器授权登录:拉起系统浏览器打开 /user-api-key/new,授权后
  /// 深链 fluxdo://auth_redirect 回 App,由 UserApiKeyLoginFlow 完成
  /// OTP 兑换与登录收口,这里只负责发起和成功后 pop。
  Future<void> _loginWithBrowserAuth() async {
    if (_browserAuthLaunching) return;
    setState(() => _browserAuthLaunching = true);
    UserApiKeyLoginFlow.instance.onFlowFinished = _onBrowserAuthFinished;
    try {
      // 首次会懒生成 RSA 密钥对(isolate),可能耗时数秒
      final launched = await UserApiKeyLoginFlow.instance.start();
      if (!launched && mounted) {
        ToastService.showError('无法打开浏览器,请重试');
      }
    } finally {
      if (mounted) setState(() => _browserAuthLaunching = false);
    }
  }

  void _onBrowserAuthFinished(bool success) {
    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final credentials = await CredentialStoreService().list();
      final recent = credentials.isEmpty ? null : credentials.first;
      if (!mounted) return;
      setState(() {
        _savedCredentials = credentials;
        _savedUsername = recent?.identifier;
        _savedPassword = recent?.password;
        _credentialsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _credentialsLoaded = true);
    }
  }

  /// 表单提交回调。返 true 表示走完成功路径并已 pop, false 留在表单。
  Future<bool> _handleSubmit({
    required String identifier,
    required String password,
    required bool rememberCredentials,
  }) async {
    final service = DiscourseService();

    // 不再预先强制要求 cf_clearance。直接登录请求本身由 WebView 内核发出；
    // 只有 /session/csrf 真正命中 Cloudflare challenge 时，dialog 才按需拉起验证。
    // 这样未启用 Cloudflare 的 Discourse 实例也能直接登录。
    // hcaptcha endpoint: 从 SharedPreferences 拿 (站长改 mount 时填到设置里);
    // 没配就让 dialog 用内置 fallback 列表 (/captcha/hcaptcha/create.json →
    // /hcaptcha/create.json)。读 prefs 直接走 SharedPreferences (不依赖
    // riverpod, LoginPage 是普通 StatefulWidget)。
    final prefs = await SharedPreferences.getInstance();
    final hcaptchaEndpoint = prefs.getString('pref_hcaptcha_create_endpoint');
    if (!mounted) return false;

    // Step 1-3: WebView 内 JS 自适应登录。
    // 先 csrf → session；只有服务端确实要求 captcha 才调用 hcaptcha/create。
    // 这样站点关闭验证码后不会继续请求已禁用 endpoint 并收到 403。
    // 2FA 通过 onNeedSecondFactor 原生处理 TOTP / 备用码。
    var fallbackToWebLogin = false;
    final result = await showWebViewLoginDialog(
      context,
      siteKey: _kLinuxDoHcaptchaSiteKey,
      identifier: identifier,
      password: password,
      hcaptchaCreateEndpoint: hcaptchaEndpoint,
      onNeedSecondFactor: (need) => showTwoFactorDialog(
        context,
        hint: need.totpEnabled ? '请选择可用的二步验证方式完成登录' : '此账号需要二步验证',
        totpEnabled: need.totpEnabled,
        backupEnabled: need.backupEnabled,
        securityKeyEnabled: need.securityKeyEnabled,
        onUseWebLogin: () => fallbackToWebLogin = true,
      ),
    );
    if (!mounted) return false;
    if (result == null || result.status == WebViewLoginStatus.canceled) {
      if (fallbackToWebLogin && mounted) {
        await _loginWithWebView();
      }
      return false;
    }

    if (result.status == WebViewLoginStatus.success) {
      // dialog 已把会话 cookie (_t/_forum_session) 同步落 jar,
      // 这里复用收尾: AuthSession.advance → setToken → 预加载数据 → 登录广播。
      await service.finalizeNativeLoginSuccess(identifier);
      // 密码按实际 Discourse username 隔离。使用邮箱登录时也不会另开一个
      // 凭证槽；取消“记住密码”则显式删除该账号此前保存的密码。
      try {
        final preloadedUsername =
            PreloadedDataService().currentUserSync?['username']
                ?.toString()
                .trim();
        final storedUsername = await AccountManager().getCurrentUsername();
        final accountId =
            preloadedUsername != null && preloadedUsername.isNotEmpty
            ? preloadedUsername
            : storedUsername;

        if (rememberCredentials) {
          await CredentialStoreService().save(
            identifier,
            password,
            accountId: accountId,
          );
        } else {
          final credentialStore = CredentialStoreService();
          await credentialStore.clear(accountId: accountId ?? identifier);
          // 兼容旧版本可能以登录邮箱作为槽 ID 的凭证。
          if (accountId != null &&
              accountId.trim().toLowerCase() !=
                  identifier.trim().toLowerCase()) {
            await credentialStore.clear(accountId: identifier);
          }
        }
      } catch (e) {
        debugPrint('[LoginPage] 更新账号密码存储失败,不影响登录: $e');
      }
      if (!mounted) return true;
      ToastService.showSuccess(S.current.webviewLogin_loginSuccess);
      Navigator.of(context).pop(true);
      return true;
    }

    // 失败 — toast 出来
    _showFailureToast(
      LoginFailure(
        result.loginErrorKind ?? LoginErrorKind.unknown,
        message: result.errorMessage,
      ),
    );
    return false;
  }

  void _showFailureToast(LoginFailure f) {
    final msg = switch (f.kind) {
      LoginErrorKind.invalidCredentials => '用户名或密码错误',
      LoginErrorKind.secondFactorRequired => f.message ?? '二步验证失败',
      LoginErrorKind.notActivated => '账号未激活,请到邮箱 ${f.sentToEmail ?? ''} 完成激活',
      LoginErrorKind.notApproved => '账号尚未通过审核',
      LoginErrorKind.passwordExpired => '密码已过期,请用浏览器登录重设密码',
      LoginErrorKind.network => f.message ?? '网络异常',
      LoginErrorKind.unknown => f.message ?? '登录失败',
    };
    ToastService.showError(msg);
  }

  Future<void> _loginWithWebView([String? initialUrl]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebViewLoginPage(initialUrl: initialUrl),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _clearSavedCredentials() async {
    await CredentialStoreService().clear();
    if (!mounted) return;
    setState(() {
      _savedCredentials = const [];
      _savedUsername = null;
      _savedPassword = null;
    });
    ToastService.showSuccess('已清除所有保存的账号密码');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: Stack(
              children: [
                // 左上返回
                Positioned(
                  top: 4,
                  left: 4,
                  child: _entry(
                    0,
                    AmbientIconButton(
                      icon: Symbols.arrow_back_rounded,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
                // 右上清除保存的账号
                if (_credentialsLoaded && _savedUsername != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _entry(
                      0,
                      AmbientIconButton(
                        icon: Symbols.delete_rounded,
                        tooltip: '清除所有保存的账号密码',
                        onPressed: _clearSavedCredentials,
                      ),
                    ),
                  ),
                // 主内容
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _entry(
                            0,
                            const Center(
                              child: FloatingLogo(size: 88, glowSize: 80),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _entry(
                            1,
                            Text(
                              'LINUX.DO',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _entry(
                            2,
                            Text(
                              context.l10n.login_slogan,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                                letterSpacing: 2,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _entry(3, _buildFormCard(theme, scheme)),
                          const SizedBox(height: 24),
                          _entry(4, _buildAltLogin(context, scheme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// staggered 入场包装 (index 对应 _fade/_slide)
  Widget _entry(int i, Widget child) {
    return FadeTransition(
      opacity: _fade[i],
      child: SlideTransition(position: _slide[i], child: child),
    );
  }

  /// 磨砂玻璃表单卡片
  Widget _buildFormCard(ThemeData theme, ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.4 : 0.1,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: createBlurFilter(blurSigma),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: !_credentialsLoaded
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: LoadingSpinner(size: 40)),
                  )
                : LoginForm(
                    onSubmit: _handleSubmit,
                    onForgotPassword: () =>
                        _loginWithWebView('https://linux.do/password-reset'),
                    savedUsername: _savedUsername,
                    savedPassword: _savedPassword,
                    savedCredentials: {
                      for (final credential in _savedCredentials)
                        credential.identifier: credential.password,
                    },
                  ),
          ),
        ),
      ),
    );
  }

  /// 分割线 + 其他方式登录 (扫码 / 浏览器授权 / OAuth 等)
  Widget _buildAltLogin(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DividerWithLabel(label: '或'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _loginWithQrScan,
          icon: const Icon(Symbols.qr_code_scanner_rounded, size: 20),
          label: Text(context.l10n.login_scanToLogin),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _browserAuthLaunching ? null : _loginWithBrowserAuth,
          icon: _browserAuthLaunching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: LoadingSpinner(size: 20),
                )
              : const Icon(Symbols.verified_user_rounded, size: 20),
          label: const Text('浏览器授权登录'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _loginWithWebView(),
          icon: const Icon(Symbols.open_in_browser_rounded, size: 20),
          label: const Text('其他方式登录 (OAuth / Passkey / 注册)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.login_browserHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  /// 扫码登录:跳转扫码页,成功后 pop 登录页
  Future<void> _loginWithQrScan() async {
    final result = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const QrLoginScanPage()));
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

class _DividerWithLabel extends StatelessWidget {
  const _DividerWithLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
