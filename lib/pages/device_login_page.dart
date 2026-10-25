import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_session.dart';
import '../services/device_authorization_service.dart';
import '../services/discourse/discourse_service.dart';
import '../services/login_token_redeemer.dart';

enum DeviceLoginResult { keyAuthorized, useBrowser }

/// Manual confirmation works on any other device. On this device the
/// request-token link opens the regular Discourse browser approval screen.
class DeviceLoginPage extends StatefulWidget {
  const DeviceLoginPage({super.key});

  @override
  State<DeviceLoginPage> createState() => _DeviceLoginPageState();
}

class _DeviceLoginPageState extends State<DeviceLoginPage> {
  late final DeviceAuthorizationService _device;
  DeviceAuthorizationRequest? _request;
  Timer? _ticker;
  bool _cancelled = false;
  bool _starting = true;
  bool _completing = false;
  String? _error;
  String? _authorizedUsername;
  String _status = '正在向 LINUX DO 申请设备授权…';

  @override
  void initState() {
    super.initState();
    _device = DeviceAuthorizationService(DiscourseService().dio);
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _ticker?.cancel();
    setState(() {
      _request = null;
      _starting = true;
      _completing = false;
      _error = null;
      _authorizedUsername = null;
      _status = '正在创建授权请求…';
    });
    try {
      final request = await _device.create();
      if (!mounted || _cancelled) return;
      setState(() {
        _request = request;
        _starting = false;
        _status = '请在浏览器确认授权，FluxDO 将自动检测结果';
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      unawaited(_poll(request));
    } on DioException catch (e) {
      _fail(
        LoginTokenRedeemer.isChallengeError(e)
            ? 'Cloudflare 安全验证未完成，请使用系统浏览器登录。'
            : (e.response?.statusCode == 403 || e.response?.statusCode == 400)
            ? '站点拒绝了原生设备 API 授权（read 权限可能未开放），请使用系统浏览器登录。'
            : '创建设备授权失败：网络或站点验证异常（${e.response?.statusCode ?? e.type}）',
      );
    } catch (e) {
      _fail('无法启动设备授权：$e');
    }
  }

  void _fail(String error) {
    if (!mounted || _cancelled) return;
    _ticker?.cancel();
    setState(() {
      _starting = false;
      _completing = false;
      _error = error;
      _status = '设备授权未完成';
    });
  }

  Future<void> _poll(DeviceAuthorizationRequest request) async {
    var consecutiveErrors = 0;
    while (mounted &&
        !_cancelled &&
        identical(_request, request) &&
        AuthSession().isValid(request.generation)) {
      if (!DateTime.now().isBefore(request.expiresAt)) {
        _fail('设备授权已过期，请重新开始');
        return;
      }
      await Future<void>.delayed(request.pollInterval);
      if (!mounted || _cancelled || !identical(_request, request)) return;
      if (!DateTime.now().isBefore(request.expiresAt)) {
        _fail('设备授权已过期，请重新开始');
        return;
      }
      try {
        final poll = await _device.poll(request);
        if (!mounted || _cancelled || !identical(_request, request)) return;
        consecutiveErrors = 0;
        switch (poll.status) {
          case DeviceAuthorizationStatus.pending:
            continue;
          case DeviceAuthorizationStatus.denied:
            _fail('浏览器中已拒绝授权');
            return;
          case DeviceAuthorizationStatus.expired:
            _fail('授权码已失效或已被使用');
            return;
          case DeviceAuthorizationStatus.authorized:
            setState(() {
              _completing = true;
              _status = '已授权，正在验证原生 User API Key…';
            });
            try {
              final identity = await _device.authorize(
                request,
                poll.encryptedPayload!,
              );
              if (!mounted || _cancelled || !identical(_request, request)) return;
              _ticker?.cancel();
              setState(() {
                _request = null;
                _authorizedUsername = identity.username;
                _completing = false;
                _status = '设备 API 授权成功：${identity.username}';
              });
            } catch (e) {
              _fail('无法验证设备 API Key：$e');
            }
            return;
        }
      } on DioException catch (e) {
        if (LoginTokenRedeemer.isChallengeError(e)) {
          _fail('设备授权轮询遇到 Cloudflare 安全验证，请改用系统浏览器登录');
          return;
        }
        consecutiveErrors++;
        if (consecutiveErrors >= 3) {
          _fail('轮询设备授权失败（${e.response?.statusCode ?? e.type}），请重新开始');
          return;
        }
      } catch (e) {
        _fail('设备授权响应异常：$e');
        return;
      }
    }
  }

  Future<void> _openApprovalPage(Uri url) async {
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) _fail('无法打开授权页面，请复制地址到浏览器');
    } catch (_) {
      _fail('无法打开授权页面，请复制地址到浏览器');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final request = _request;
    final remaining = request == null
        ? 0
        : request.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 600);
    return Scaffold(
      appBar: AppBar(title: const Text('设备授权登录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.phonelink_lock_outlined, size: 56),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (_starting || _completing) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 20),
              ],
              if (request != null && _authorizedUsername == null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          '在 LINUX DO 中输入此授权码',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          request.userCode,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                letterSpacing: 3,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '剩余约 ${(remaining / 60).ceil()} 分钟',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _completing
                              ? null
                              : () => _openApprovalPage(
                                  request.verificationUriWithRequest,
                                ),
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('在浏览器确认授权'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    '${request.verificationUri}\n${request.userCode}',
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('复制授权地址及授权码'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '授权将在浏览器进行。请核对应用名 FluxDO Device API '
                  '和只读 read 权限。此流程获取原生 User API Key，'
                  '不会生成 Cookie 登录会话。',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
              if (_authorizedUsername != null) ...[
                const SizedBox(height: 16),
                Text(
                  '已安全保存只读 User API Key。FluxDO 当前主会话仍使用 '
                  '_t Cookie，此授权不会自动切换或创建登录账号。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(
                    DeviceLoginResult.useBrowser,
                  ),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('继续使用系统浏览器完成登录'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    DeviceLoginResult.keyAuthorized,
                  ),
                  child: const Text('返回登录页面'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: scheme.error)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    _cancelled = false;
                    _start();
                  },
                  child: const Text('重新尝试'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      Navigator.of(context).pop(DeviceLoginResult.useBrowser),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('改用系统浏览器登录'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
