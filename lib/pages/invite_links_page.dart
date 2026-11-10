import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../constants.dart';
import '../models/invite_draft.dart';
import '../models/invite_link.dart';
import '../models/user.dart';
import '../providers/discourse_providers.dart';
import '../providers/theme_provider.dart';
import '../services/network/exceptions/api_exception.dart';
import '../services/toast_service.dart';
import '../utils/time_utils.dart';
import '../l10n/s.dart';

enum _InviteExpiryPreset { days1, days7, days30, days90 }

extension on _InviteExpiryPreset {
  String get label {
    switch (this) {
      case _InviteExpiryPreset.days1:
        return S.current.time_days(1);
      case _InviteExpiryPreset.days7:
        return S.current.time_days(7);
      case _InviteExpiryPreset.days30:
        return S.current.time_days(30);
      case _InviteExpiryPreset.days90:
        return S.current.time_days(90);
    }
  }

  Duration? get duration {
    switch (this) {
      case _InviteExpiryPreset.days1:
        return const Duration(days: 1);
      case _InviteExpiryPreset.days7:
        return const Duration(days: 7);
      case _InviteExpiryPreset.days30:
        return const Duration(days: 30);
      case _InviteExpiryPreset.days90:
        return const Duration(days: 90);
    }
  }
}

class InviteLinksPage extends ConsumerStatefulWidget {
  const InviteLinksPage({super.key});

  @override
  ConsumerState<InviteLinksPage> createState() => _InviteLinksPageState();
}

class _InviteLinksPageState extends ConsumerState<InviteLinksPage> {
  static const int _maxRedemptionsAllowed = 1;
  static final String _defaultRateLimitWait = S.current.time_hours(21);
  static const Duration _inviteCooldownDuration = Duration(hours: 24);
  static const String _inviteCacheKeyPrefix = 'invite_link_cache:';

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _restrictionController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _customMessageController = TextEditingController();
  final TextEditingController _maxRedemptionsController = TextEditingController(
    text: '1',
  );

  InviteDeliveryMethod _inviteMethod = InviteDeliveryMethod.link;
  String? _lastEmailRecipient;
  _InviteExpiryPreset _expiryPreset = _InviteExpiryPreset.days1;
  bool _showAdvancedOptions = false;
  bool _isSubmitting = false;
  bool _isLoadingPending = false;
  bool _isManagingInvite = false;
  InviteLinkResponse? _latestInvite;
  ProviderSubscription<AsyncValue<User?>>? _userSub;
  bool _hasRequestedInitialRefresh = false;

  @override
  void initState() {
    super.initState();
    _userSub = ref.listenManual<AsyncValue<User?>>(currentUserProvider, (
      _,
      next,
    ) {
      final user = next.value;
      if (user == null) return;
      _applyCachedInvite(user.username);
      if (!_hasRequestedInitialRefresh) {
        _hasRequestedInitialRefresh = true;
        Future.microtask(() => _loadPendingInvites(force: true));
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _restrictionController.dispose();
    _emailController.dispose();
    _customMessageController.dispose();
    _maxRedemptionsController.dispose();
    _userSub?.close();
    super.dispose();
  }

  DateTime? get _expiresAt {
    final duration = _expiryPreset.duration;
    if (duration == null) return null;
    return DateTime.now().add(duration);
  }

  String? get _effectiveInviteLink {
    final link = _latestInvite?.inviteLink.trim() ?? '';
    if (link.isNotEmpty) return link;
    final key = _latestInvite?.invite?.inviteKey?.trim();
    if (key != null && key.isNotEmpty) {
      return _buildInviteLink(key);
    }
    return null;
  }

  bool get _hasInviteLink =>
      (_latestInvite?.invite?.email?.trim().isEmpty ?? true) &&
      (_effectiveInviteLink?.isNotEmpty ?? false);

  String _buildInviteLink(String key) {
    return '${AppConstants.baseUrl}/invites/$key';
  }

  InviteLinkResponse _resolveInviteLink(InviteLinkResponse invite) {
    final link = invite.inviteLink.trim();
    if (link.isNotEmpty) return invite;
    final key = invite.invite?.inviteKey?.trim();
    if (key != null && key.isNotEmpty) {
      return InviteLinkResponse(
        inviteLink: _buildInviteLink(key),
        invite: invite.invite,
      );
    }
    return invite;
  }

  InviteLinkResponse? _pickLatestInvite(List<InviteLinkResponse> invites) {
    // 邮箱邀请不作为可分享的链接展示，避免将定向邀请误分享。
    final links = invites.where((invite) {
      final email = invite.invite?.email?.trim() ?? '';
      return email.isEmpty;
    }).toList();
    if (links.isEmpty) return null;
    return links.reduce((a, b) {
      final aTime =
          a.invite?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.invite?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.isAfter(aTime) ? b : a;
    });
  }

  String _inviteIdentity(InviteLinkResponse? invite) {
    if (invite == null) return '';
    final key = invite.invite?.inviteKey?.trim();
    if (key != null && key.isNotEmpty) {
      return 'key:$key';
    }
    final link = invite.inviteLink.trim();
    if (link.isNotEmpty) {
      return 'link:$link';
    }
    return '';
  }

  bool _isSameInvite(InviteLinkResponse? a, InviteLinkResponse? b) {
    return _inviteIdentity(a) == _inviteIdentity(b);
  }

  String _inviteCacheKey(String username) {
    return '$_inviteCacheKeyPrefix$username';
  }

  InviteLinkResponse? _readCachedInvite(String username) {
    final prefs = ref.read(sharedPreferencesProvider);
    final cached = prefs.getString(_inviteCacheKey(username));
    if (cached == null || cached.isEmpty) return null;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is Map<String, dynamic>) {
        return _resolveInviteLink(InviteLinkResponse.fromJson(decoded));
      }
      if (decoded is Map) {
        return _resolveInviteLink(
          InviteLinkResponse.fromJson(Map<String, dynamic>.from(decoded)),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveInviteCache(
    String username,
    InviteLinkResponse invite,
  ) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final payload = jsonEncode(invite.toJson());
    await prefs.setString(_inviteCacheKey(username), payload);
  }

  Future<void> _clearInviteCache(String username) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_inviteCacheKey(username));
  }

  void _applyCachedInvite(String username) {
    if (_latestInvite != null) return;
    final cached = _readCachedInvite(username);
    if (cached == null || !mounted) return;
    setState(() => _latestInvite = cached);
  }

  Future<void> _loadPendingInvites({bool force = false}) async {
    if (_isLoadingPending) return;
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    setState(() => _isLoadingPending = true);
    try {
      final invites = await ref
          .read(discourseServiceProvider)
          .getPendingInvites(user.username);
      final latest = _pickLatestInvite(invites);
      final resolved = latest != null ? _resolveInviteLink(latest) : null;
      if (!_isSameInvite(_latestInvite, resolved) && mounted) {
        setState(() => _latestInvite = resolved);
        if (resolved != null) {
          await _saveInviteCache(user.username, resolved);
        } else {
          await _clearInviteCache(user.username);
        }
      }
    } catch (_) {
      // 忽略失败，避免干扰手动创建流程
    } finally {
      if (mounted) {
        setState(() => _isLoadingPending = false);
      }
    }
  }

  Future<void> _createInvite() async {
    if (_isSubmitting) return;
    final user = ref.read(currentUserProvider).value;
    if (user == null) {
      ToastService.showError(S.current.common_pleaseLogin);
      return;
    }
    if (user.trustLevel < 3) {
      ToastService.showError(S.current.invite_trustLevelTooLow);
      return;
    }

    final draft = InviteDraft(
      method: _inviteMethod,
      advanced: _showAdvancedOptions,
      emailInput: _emailController.text,
      domainInput: _restrictionController.text,
      maxRedemptionsInput: _maxRedemptionsController.text,
      descriptionInput: _descriptionController.text,
      customMessageInput: _customMessageController.text,
    );
    final strings = _InviteFormStrings.of(context);
    final error = switch (draft.validation) {
      InviteDraftValidation.invalidEmail => strings.invalidEmail,
      InviteDraftValidation.invalidDomain => strings.invalidDomain,
      InviteDraftValidation.invalidRedemptions => strings.invalidRedemptions,
      null => null,
    };
    if (error != null) {
      ToastService.showError(error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 简单模式固定使用 1 天，不能泄漏上次高级模式的配置。
      final expiresAt = _showAdvancedOptions
          ? _expiresAt
          : DateTime.now().add(const Duration(days: 1));
      final result = await ref.read(discourseServiceProvider).createInviteLink(
        maxRedemptionsAllowed: draft.maxRedemptionsAllowed,
        expiresAt: expiresAt,
        description: draft.description,
        email: draft.email,
        domain: draft.domain,
        customMessage: draft.customMessage,
      );
      if (!mounted) return;

      if (draft.method == InviteDeliveryMethod.email) {
        setState(() => _lastEmailRecipient = draft.email);
        await _loadPendingInvites(force: true);
        if (mounted) ToastService.showSuccess(strings.emailSent);
        return;
      }

      final resolved = _resolveInviteLink(result);
      final link = resolved.inviteLink.trim();
      if (link.isEmpty) {
        await _loadPendingInvites(force: true);
        if (mounted) ToastService.showSuccess(S.current.invite_created);
        return;
      }

      setState(() => _latestInvite = resolved);
      try {
        await _saveInviteCache(user.username, resolved);
      } catch (_) {
        // 缓存失败不应阻止已经创建成功的邀请链接复制。
      }
      if (!mounted) return;

      try {
        await Clipboard.setData(ClipboardData(text: link));
        if (mounted) ToastService.showSuccess(S.current.invite_linkCopied);
      } catch (_) {
        // 创建已成功，复制失败时仍可从下方结果卡片手动复制。
        if (mounted) ToastService.showSuccess(S.current.invite_linkGenerated);
      }
    } catch (error) {
      if (!mounted) return;
      ToastService.showError(_normalizeErrorMessage(error));
      if (_latestInvite == null) {
        await _loadPendingInvites(force: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _copyInviteLink() async {
    final inviteLink = _effectiveInviteLink;
    if (inviteLink == null || inviteLink.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: inviteLink));
    ToastService.showSuccess(S.current.invite_linkCopied);
  }

  void _shareInviteLink() {
    final inviteLink = _effectiveInviteLink;
    if (inviteLink == null || inviteLink.isEmpty) return;
    SharePlus.instance.share(
      ShareParams(text: inviteLink, subject: S.current.invite_shareSubject),
    );
  }

  String _normalizeErrorMessage(Object error) {
    if (error is RateLimitException) {
      final waitSeconds = error.retryAfterSeconds;
      final waitFromMessage = _extractWaitText(error.toString());
      final estimatedWait = _estimateInviteCooldownWait();
      final waitText = waitSeconds != null && waitSeconds > 0
          ? _formatWaitDuration(waitSeconds)
          : (waitFromMessage ?? estimatedWait ?? _defaultRateLimitWait);
      return S.current.invite_rateLimited(waitText);
    }

    final message = _extractErrorMessage(error);
    final rateLimitMessage = _buildRateLimitMessage(error, message);
    if (rateLimitMessage != null) {
      return rateLimitMessage;
    }
    if (message.contains('You are not permitted') ||
        message.contains('not permitted')) {
      return S.current.invite_permissionDenied;
    }
    return message.isEmpty ? S.current.invite_createFailed : message;
  }

  String _extractErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map &&
          data['errors'] is List &&
          (data['errors'] as List).isNotEmpty) {
        return _cleanErrorMessage((data['errors'] as List).join('\n'));
      }
      if (data is Map && data['message'] is String) {
        return _cleanErrorMessage(data['message'] as String);
      }
      if (data is String && data.trim().isNotEmpty) {
        return _cleanErrorMessage(data.trim());
      }
      return _cleanErrorMessage((error.message ?? error.toString()).trim());
    }
    return _cleanErrorMessage(
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim(),
    );
  }

  String _cleanErrorMessage(String message) {
    var result = message.trim();
    result = result.replaceFirst(RegExp(r'^DioException[^:]*:\s*'), '');
    result = result.replaceFirst(RegExp(r'^\s*null\s*Error\s*'), '');
    result = result.replaceFirst(RegExp(r'^\s*Error\s*'), '');
    return result.trim();
  }

  String? _buildRateLimitMessage(Object error, String message) {
    final normalized = message.toLowerCase();
    final dioError = error is DioException ? error : null;
    final isRateLimited =
        normalized.contains('too many times') ||
        normalized.contains('too many requests') ||
        normalized.contains('rate limit') ||
        normalized.contains('rate limited') ||
        normalized.contains('request too many') ||
        normalized.contains('请求过多') ||
        normalized.contains('请求过于频繁') ||
        normalized.contains('请求频繁') ||
        normalized.contains('次数过多') ||
        normalized.contains('请稍候') ||
        dioError?.response?.statusCode == 429;

    if (!isRateLimited) return null;

    if (message.contains('您执行此操作的次数过多')) {
      if (message.startsWith('出错了：')) {
        return message;
      }
      final cleaned = message.replaceFirst(RegExp(r'^[:：]+'), '');
      return '出错了：$cleaned';
    }

    final waitText =
        _extractWaitText(message) ??
        _extractWaitTextFromData(dioError?.response?.data) ??
        _extractWaitTextFromHeaders(dioError?.response?.headers) ??
        _estimateInviteCooldownWait() ??
        _defaultRateLimitWait;
    if (waitText == S.current.time_hours(21)) {
      return S.current.invite_rateLimited(S.current.time_hours(21));
    }
    return S.current.invite_rateLimited(waitText);
  }

  String? _estimateInviteCooldownWait() {
    final createdAt = _latestInvite?.invite?.createdAt;
    if (createdAt == null) return null;
    final elapsed = DateTime.now().difference(createdAt);
    final remaining = _inviteCooldownDuration - elapsed;
    if (remaining.inSeconds <= 0) return null;
    return _formatWaitDuration(remaining.inSeconds);
  }

  String? _extractWaitTextFromHeaders(Headers? headers) {
    if (headers == null) return null;
    final retryAfter =
        headers.value('retry-after') ?? headers.value('Retry-After');
    final retrySeconds = int.tryParse(retryAfter ?? '');
    if (retrySeconds != null && retrySeconds > 0) {
      return _formatWaitDuration(retrySeconds);
    }

    final resetValue =
        headers.value('x-ratelimit-reset') ??
        headers.value('ratelimit-reset') ??
        headers.value('x-rate-limit-reset') ??
        headers.value('X-RateLimit-Reset');
    final resetSeconds = int.tryParse(resetValue ?? '');
    if (resetSeconds != null && resetSeconds > 0) {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final delta = resetSeconds > 1000000000
          ? (resetSeconds - nowSeconds)
          : resetSeconds;
      if (delta > 0) {
        return _formatWaitDuration(delta);
      }
    }
    return null;
  }

  String? _extractWaitTextFromData(dynamic data) {
    if (data is Map) {
      final errors = data['errors'];
      if (errors is List) {
        for (final item in errors) {
          final text = _extractWaitText(item.toString());
          if (text != null) return text;
        }
      }
      final extras = data['extras'];
      if (extras is Map) {
        final waitSecondsRaw = extras['wait_seconds'] ?? extras['time_left'];
        final waitSeconds = int.tryParse(waitSecondsRaw?.toString() ?? '');
        if (waitSeconds != null && waitSeconds > 0) {
          return _formatWaitDuration(waitSeconds);
        }
      }
    }
    if (data is String) {
      return _extractWaitText(data);
    }
    return null;
  }

  String? _extractWaitText(String message) {
    final chineseMatch = RegExp(r'请等待\s*([0-9]+\s*(?:小时|分钟|天|秒))\s*后再试')
        .firstMatch(message);
    if (chineseMatch != null) {
      return chineseMatch.group(1);
    }

    final englishMatch = RegExp(
      r'Please wait\s+(\d+)\s+(second|seconds|minute|minutes|hour|hours|day|days)\s+before trying again',
      caseSensitive: false,
    ).firstMatch(message);
    if (englishMatch != null) {
      final value = int.tryParse(englishMatch.group(1) ?? '');
      final unit = englishMatch.group(2)?.toLowerCase();
      if (value == null || unit == null) return null;
      if (unit.startsWith('day')) return S.current.time_days(value);
      if (unit.startsWith('hour')) return S.current.time_hours(value);
      if (unit.startsWith('minute')) return S.current.time_minutes(value);
      return S.current.time_seconds(value);
    }

    return null;
  }

  String _formatWaitDuration(int seconds) {
    if (seconds >= 86400) {
      return S.current.time_days((seconds / 86400).ceil());
    }
    if (seconds >= 3600) {
      return S.current.time_hours((seconds / 3600).ceil());
    }
    if (seconds >= 60) {
      return S.current.time_minutes((seconds / 60).ceil());
    }
    return S.current.time_seconds(seconds);
  }

  Future<void> _deleteLatestInvite() async {
    final details = _latestInvite?.invite;
    final id = details?.id;
    if (id == null || details?.canDeleteInvite == false || _isManagingInvite) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除邀请'),
            content: const Text('确定删除这个待使用邀请吗？邀请链接将立即失效。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _isManagingInvite = true);
    try {
      await ref.read(discourseServiceProvider).deleteInvite(id);
      final user = ref.read(currentUserProvider).value;
      if (user != null) await _clearInviteCache(user.username);
      if (!mounted) return;
      setState(() => _latestInvite = null);
      await _loadPendingInvites(force: true);
      ToastService.showSuccess('邀请已删除');
    } catch (e) {
      ToastService.showError('删除失败: $e');
    } finally {
      if (mounted) setState(() => _isManagingInvite = false);
    }
  }

  Future<void> _resendLatestInvite() async {
    final email = _latestInvite?.invite?.email?.trim();
    if (email == null || email.isEmpty || _isManagingInvite) return;
    setState(() => _isManagingInvite = true);
    try {
      await ref.read(discourseServiceProvider).resendInvite(email);
      ToastService.showSuccess('邀请邮件已重新发送');
    } catch (e) {
      ToastService.showError('重新发送失败: $e');
    } finally {
      if (mounted) setState(() => _isManagingInvite = false);
    }
  }

  Future<void> _resendAllInvites() async {
    if (_isManagingInvite) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('重新发送全部邀请'),
            content: const Text('将重新发送所有仍处于待处理状态的邮件邀请。继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('重新发送'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _isManagingInvite = true);
    try {
      await ref.read(discourseServiceProvider).resendAllInvites();
      ToastService.showSuccess('待处理邀请已重新发送');
    } catch (e) {
      ToastService.showError('重新发送失败: $e');
    } finally {
      if (mounted) setState(() => _isManagingInvite = false);
    }
  }

  Future<void> _editLatestInvite() async {
    final details = _latestInvite?.invite;
    final id = details?.id;
    if (id == null || _isManagingInvite) return;

    final descriptionController = TextEditingController(
      text: details?.description ?? '',
    );
    final emailController = TextEditingController(text: details?.email ?? '');
    final result = await showDialog<({String description, String email})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑邀请'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descriptionController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '限定邮箱（留空则取消邮箱限定）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              description: descriptionController.text.trim(),
              email: emailController.text.trim(),
            )),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    descriptionController.dispose();
    emailController.dispose();
    if (result == null || !mounted) return;

    setState(() => _isManagingInvite = true);
    try {
      final updated = await ref
          .read(discourseServiceProvider)
          .updateInvite(
            id,
            description: result.description,
            email: result.email,
          );
      final resolved = _resolveInviteLink(updated);
      if (!mounted) return;
      setState(() => _latestInvite = resolved);
      final user = ref.read(currentUserProvider).value;
      if (user != null) await _saveInviteCache(user.username, resolved);
      ToastService.showSuccess('邀请已更新');
    } catch (e) {
      ToastService.showError('更新失败: $e');
    } finally {
      if (mounted) setState(() => _isManagingInvite = false);
    }
  }

  Future<void> _createBulkEmailInvites() async {
    if (_isManagingInvite) return;
    final emailsController = TextEditingController();
    final messageController = TextEditingController();
    final result = await showDialog<({List<String> emails, String message})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量邮件邀请'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailsController,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '邮箱地址',
                  hintText: '每行一个，也可用逗号、分号或空格分隔',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '自定义消息（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final emails = emailsController.text
                  .split(RegExp(r'[\s,;，；]+'))
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toSet()
                  .toList(growable: false);
              if (emails.isEmpty) return;
              Navigator.pop(dialogContext, (
                emails: emails,
                message: messageController.text.trim(),
              ));
            },
            child: const Text('发送邀请'),
          ),
        ],
      ),
    );
    emailsController.dispose();
    messageController.dispose();
    if (result == null || !mounted) return;

    setState(() => _isManagingInvite = true);
    try {
      final response = await ref
          .read(discourseServiceProvider)
          .createMultipleInvites(
            emails: result.emails,
            customMessage: result.message.isEmpty ? null : result.message,
            expiresAt: _expiresAt,
          );
      final success =
          (response['num_successfully_created_invitations'] as num?)?.toInt() ??
          0;
      final failed = (response['num_failed_invitations'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      await _loadPendingInvites(force: true);
      ToastService.showSuccess('批量邀请完成：成功 $success，失败 $failed');
    } catch (e) {
      ToastService.showError('批量邀请失败: $e');
    } finally {
      if (mounted) setState(() => _isManagingInvite = false);
    }
  }

  Future<void> _destroyExpiredInvites() async {
    if (_isManagingInvite) return;
    setState(() => _isManagingInvite = true);
    try {
      final user = ref.read(currentUserProvider).value;
      await ref
          .read(discourseServiceProvider)
          .destroyAllExpiredInvites(username: user?.username);
      if (!mounted) return;
      await _loadPendingInvites(force: true);
      ToastService.showSuccess('已清理过期邀请');
    } catch (e) {
      ToastService.showError('清理失败: $e');
    } finally {
      if (mounted) setState(() => _isManagingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.invite_inviteMembers),
        actions: [
          PopupMenuButton<String>(
            enabled: !_isManagingInvite,
            onSelected: (value) {
              if (value == 'bulk_invite') _createBulkEmailInvites();
              if (value == 'resend_all') _resendAllInvites();
              if (value == 'clear_expired') _destroyExpiredInvites();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bulk_invite', child: Text('批量邮件邀请')),
              PopupMenuItem(value: 'resend_all', child: Text('重新发送全部待处理邀请')),
              PopupMenuItem(value: 'clear_expired', child: Text('清理过期邀请')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCreateForm(theme),
                  if (_inviteMethod == InviteDeliveryMethod.email &&
                      _lastEmailRecipient != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.mark_email_read_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(_InviteFormStrings.of(context).emailSent),
                        subtitle: Text(_lastEmailRecipient!),
                      ),
                    ),
                  ],
                  if (_inviteMethod == InviteDeliveryMethod.link &&
                      _hasInviteLink) ...[
                    const SizedBox(height: 16),
                    _buildResultCard(theme),
                  ] else if (!_isLoadingPending &&
                      _inviteMethod == InviteDeliveryMethod.link) ...[
                    const SizedBox(height: 16),
                    _buildEmptyStateCard(theme),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildActionBar(theme),
    );
  }

  Widget _buildCreateForm(ThemeData theme) {
    final strings = _InviteFormStrings.of(context);
    final isEmail = _inviteMethod == InviteDeliveryMethod.email;
    final labelStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      key: const Key('invite-create-form'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.inviteMethod, style: labelStyle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('invite-method-link'),
                  avatar: const Icon(Icons.link_rounded, size: 18),
                  label: Text(strings.shareLink),
                  selected: !isEmail,
                  onSelected: _isSubmitting
                      ? null
                      : (_) => setState(
                          () => _inviteMethod = InviteDeliveryMethod.link,
                        ),
                ),
                ChoiceChip(
                  key: const Key('invite-method-email'),
                  avatar: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: Text(strings.email),
                  selected: isEmail,
                  onSelected: _isSubmitting
                      ? null
                      : (_) => setState(
                          () => _inviteMethod = InviteDeliveryMethod.email,
                        ),
                ),
              ],
            ),
            if (isEmail) ...[
              const SizedBox(height: 24),
              Text(strings.sendTo, style: labelStyle),
              const SizedBox(height: 4),
              Text(strings.sendToHelp, style: helperStyle),
              const SizedBox(height: 8),
              TextField(
                key: const Key('invite-email'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'name@example.com',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_showAdvancedOptions) ...[
              if (!isEmail) ...[
                const SizedBox(height: 24),
                Text(strings.domain, style: labelStyle),
                const SizedBox(height: 4),
                Text(strings.domainHelp, style: helperStyle),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('invite-domain'),
                  controller: _restrictionController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(context.l10n.invite_maxRedemptions, style: labelStyle),
                const SizedBox(height: 8),
                SizedBox(
                  width: 140,
                  child: TextField(
                    key: const Key('invite-max-redemptions'),
                    controller: _maxRedemptionsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 24),
                Text(strings.customMessage, style: labelStyle),
                const SizedBox(height: 4),
                Text(strings.customMessageHelp, style: helperStyle),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('invite-custom-message'),
                  controller: _customMessageController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: strings.customMessageHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(context.l10n.invite_description, style: labelStyle),
              const SizedBox(height: 4),
              Text(strings.descriptionHelp, style: helperStyle),
              const SizedBox(height: 8),
              TextField(
                key: const Key('invite-description'),
                controller: _descriptionController,
                maxLength: 100,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.invite_expiryTime, style: labelStyle),
              const SizedBox(height: 8),
              DropdownButtonFormField<_InviteExpiryPreset>(
                key: const Key('invite-expiry'),
                initialValue: _expiryPreset,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _InviteExpiryPreset.values
                    .map(
                      (preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      ),
                    )
                    .toList(),
                onChanged: (preset) {
                  if (preset != null) setState(() => _expiryPreset = preset);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(ThemeData theme) {
    final strings = _InviteFormStrings.of(context);
    final isEmail = _inviteMethod == InviteDeliveryMethod.email;
    final submit = FilledButton.icon(
      key: const Key('invite-submit'),
      onPressed: _isSubmitting ? null : _createInvite,
      icon: _isSubmitting
          ? const LoadingSpinner(size: 18)
          : Icon(isEmail ? Icons.send_rounded : Icons.content_copy_rounded),
      label: Text(
        _isSubmitting
            ? context.l10n.invite_creating
            : (isEmail ? strings.send : strings.copyLink),
      ),
    );
    final cancel = TextButton(
      onPressed: _isSubmitting ? null : () => Navigator.of(context).maybePop(),
      child: Text(strings.cancel),
    );
    final mode = OutlinedButton.icon(
      key: const Key('invite-mode-toggle'),
      onPressed: _isSubmitting
          ? null
          : () => setState(
              () => _showAdvancedOptions = !_showAdvancedOptions,
            ),
      icon: const Icon(Icons.settings_outlined),
      label: Text(
        _showAdvancedOptions ? strings.simpleMode : strings.advancedMode,
      ),
    );

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 460) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: submit),
                        const SizedBox(width: 8),
                        cancel,
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight, child: mode),
                  ],
                );
              }
              return Row(
                children: [
                  submit,
                  const SizedBox(width: 8),
                  cancel,
                  const Spacer(),
                  mode,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final invite = _latestInvite!;
    final inviteLink = _effectiveInviteLink ?? invite.inviteLink;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.invite_latestResult,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                inviteLink,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: Symbols.repeat_rounded,
                  label: context.l10n.invite_usableCount(
                    invite.invite?.maxRedemptionsAllowed ??
                        _maxRedemptionsAllowed,
                  ),
                ),
                if (invite.invite?.expiresAt != null)
                  _MetaChip(
                    icon: Symbols.schedule_rounded,
                    label: context.l10n.invite_expiryDate(
                      TimeUtils.formatDetailTime(invite.invite!.expiresAt),
                    ),
                  )
                else
                  _MetaChip(
                    icon: Symbols.all_inclusive_rounded,
                    label: context.l10n.invite_noExpiry,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyInviteLink,
                    icon: const Icon(Symbols.content_copy_rounded),
                    label: Text(context.l10n.common_copyLink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _shareInviteLink,
                    icon: const Icon(Symbols.share_rounded),
                    label: Text(context.l10n.common_share),
                  ),
                ),
              ],
            ),
            if ((invite.invite?.email?.trim().isNotEmpty ?? false) ||
                (invite.invite?.id != null &&
                    invite.invite?.canDeleteInvite != false)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (invite.invite?.id != null)
                    OutlinedButton.icon(
                      onPressed: _isManagingInvite ? null : _editLatestInvite,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑邀请'),
                    ),
                  if (invite.invite?.email?.trim().isNotEmpty ?? false)
                    OutlinedButton.icon(
                      onPressed: _isManagingInvite ? null : _resendLatestInvite,
                      icon: const Icon(Icons.forward_to_inbox_outlined),
                      label: const Text('重新发送邮件'),
                    ),
                  if (invite.invite?.id != null &&
                      invite.invite?.canDeleteInvite != false)
                    OutlinedButton.icon(
                      onPressed: _isManagingInvite ? null : _deleteLatestInvite,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除邀请'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.invite_noLinks,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Local labels for the invite composer; no generated localization files needed.
class _InviteFormStrings {
  const _InviteFormStrings({
    required this.inviteMethod,
    required this.shareLink,
    required this.email,
    required this.sendTo,
    required this.sendToHelp,
    required this.domain,
    required this.domainHelp,
    required this.customMessage,
    required this.customMessageHelp,
    required this.customMessageHint,
    required this.descriptionHelp,
    required this.copyLink,
    required this.send,
    required this.cancel,
    required this.advancedMode,
    required this.simpleMode,
    required this.invalidEmail,
    required this.invalidDomain,
    required this.invalidRedemptions,
    required this.emailSent,
  });

  const _InviteFormStrings.zh()
      : this(
          inviteMethod: '邀请方式',
          shareLink: '可分享链接',
          email: '电子邮件',
          sendTo: '发送至',
          sendToHelp: '我们将向此电子邮件地址发送邀请链接。',
          domain: '限制为域名（可选）',
          domainHelp: '只有拥有此域名下电子邮箱的用户才能接受此链接。',
          customMessage: '自定义消息（可选）',
          customMessageHelp: '包含在邀请电子邮件中。',
          customMessageHint: '在您的邀请中添加个人备注',
          descriptionHelp: '可以帮助您识别此邀请的备注。',
          copyLink: '复制链接',
          send: '发送',
          cancel: '取消',
          advancedMode: '高级模式',
          simpleMode: '简单模式',
          invalidEmail: '请输入有效的电子邮件地址',
          invalidDomain: '请输入有效的域名，如 example.com',
          invalidRedemptions: '最大使用次数必须为正整数',
          emailSent: '邀请邮件已发送',
        );

  const _InviteFormStrings.zhHk()
      : this(
          inviteMethod: '邀請方式',
          shareLink: '可分享連結',
          email: '電子郵件',
          sendTo: '傳送至',
          sendToHelp: '我們將向此電子郵件地址傳送邀請連結。',
          domain: '限制為網域（可選）',
          domainHelp: '只有擁有此網域下電郵地址的用戶才能接受此連結。',
          customMessage: '自訂訊息（可選）',
          customMessageHelp: '包含在邀請電郵中。',
          customMessageHint: '在您的邀請中加入個人備註',
          descriptionHelp: '可以幫助您識別此邀請的備註。',
          copyLink: '複製連結',
          send: '傳送',
          cancel: '取消',
          advancedMode: '進階模式',
          simpleMode: '簡單模式',
          invalidEmail: '請輸入有效的電子郵件地址',
          invalidDomain: '請輸入有效的網域，例如 example.com',
          invalidRedemptions: '最多使用次數必須為正整數',
          emailSent: '邀請電郵已傳送',
        );

  const _InviteFormStrings.zhTw()
      : this(
          inviteMethod: '邀請方式',
          shareLink: '可分享連結',
          email: '電子郵件',
          sendTo: '寄送至',
          sendToHelp: '我們將向此電子郵件地址寄送邀請連結。',
          domain: '限制為網域（選填）',
          domainHelp: '只有擁有此網域下電子郵件地址的使用者才能接受此連結。',
          customMessage: '自訂訊息（選填）',
          customMessageHelp: '包含在邀請電子郵件中。',
          customMessageHint: '在您的邀請中加入個人備註',
          descriptionHelp: '可以幫助您辨識此邀請的備註。',
          copyLink: '複製連結',
          send: '寄送',
          cancel: '取消',
          advancedMode: '進階模式',
          simpleMode: '簡單模式',
          invalidEmail: '請輸入有效的電子郵件地址',
          invalidDomain: '請輸入有效的網域，例如 example.com',
          invalidRedemptions: '最大使用次數必須為正整數',
          emailSent: '邀請電子郵件已寄送',
        );

  const _InviteFormStrings.en()
      : this(
          inviteMethod: 'Invitation method',
          shareLink: 'Shareable link',
          email: 'Email',
          sendTo: 'Send to',
          sendToHelp: 'We will send an invitation link to this email address.',
          domain: 'Restrict to domain (optional)',
          domainHelp: 'Only people with an email address on this domain can use this link.',
          customMessage: 'Custom message (optional)',
          customMessageHelp: 'Included in the invitation email.',
          customMessageHint: 'Add a personal note to your invitation',
          descriptionHelp: 'A note to help you identify this invitation.',
          copyLink: 'Copy link',
          send: 'Send',
          cancel: 'Cancel',
          advancedMode: 'Advanced mode',
          simpleMode: 'Simple mode',
          invalidEmail: 'Enter a valid email address',
          invalidDomain: 'Enter a valid domain, e.g. example.com',
          invalidRedemptions: 'Maximum uses must be a positive integer',
          emailSent: 'Invitation email sent',
        );

  static _InviteFormStrings of(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag().toLowerCase();
    if (locale.startsWith('zh-hk')) return const _InviteFormStrings.zhHk();
    if (locale.startsWith('zh-tw')) return const _InviteFormStrings.zhTw();
    if (locale.startsWith('zh')) return const _InviteFormStrings.zh();
    return const _InviteFormStrings.en();
  }

  final String inviteMethod;
  final String shareLink;
  final String email;
  final String sendTo;
  final String sendToHelp;
  final String domain;
  final String domainHelp;
  final String customMessage;
  final String customMessageHelp;
  final String customMessageHint;
  final String descriptionHelp;
  final String copyLink;
  final String send;
  final String cancel;
  final String advancedMode;
  final String simpleMode;
  final String invalidEmail;
  final String invalidDomain;
  final String invalidRedemptions;
  final String emailSent;
}
