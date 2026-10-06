import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/mobile_post_source_preferences.dart';
import '../../providers/preload_cache_preferences.dart';
import '../../providers/quick_reading_preferences.dart';
import '../../services/mobile_post_source_service.dart';
import '../../services/preload_cache_service.dart';
import 'account_quick_switcher_appearance_defs.dart';
import '../settings_model.dart';

/// 自定义设置数据声明。
List<SettingsGroup> buildCustomSettingsGroups(BuildContext context) {
  final copy = _CustomSettingsCopy.of(context);
  return [
    SettingsGroup(
      title: copy.cacheGroupTitle,
      icon: Symbols.cleaning_services_rounded,
      items: [
        SwitchModel(
          id: 'preloadCache',
          title: copy.preloadCacheTitle,
          subtitle: copy.preloadCacheDescription,
          icon: Symbols.speed_rounded,
          getValue: (ref) => ref.watch(preloadCachePreferencesProvider).enabled,
          onChanged: (ref, value) => ref
              .read(preloadCachePreferencesProvider.notifier)
              .setEnabled(value),
        ),
        ActionModel(
          id: 'clearPreloadCache',
          title: copy.clearPreloadCacheTitle,
          subtitle: copy.clearPreloadCacheDescription,
          icon: Symbols.cleaning_services_rounded,
          wrapSubtitle: true,
          onTap: (context, ref) {
            unawaited(() async {
              try {
                await PreloadCacheService().clearAll();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(copy.preloadCacheCleared)),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(copy.preloadCacheClearFailed)),
                );
              }
            }());
          },
        ),
      ],
    ),
    SettingsGroup(
      title: copy.readingGroupTitle,
      icon: Symbols.auto_stories_rounded,
      items: [
        SwitchModel(
          id: 'quickReading',
          title: copy.quickReadingTitle,
          subtitle: copy.quickReadingDescription,
          icon: Symbols.speed_rounded,
          getValue: (ref) => ref.watch(quickReadingPreferencesProvider).enabled,
          onChanged: (ref, value) => ref
              .read(quickReadingPreferencesProvider.notifier)
              .setEnabled(value),
        ),
      ],
    ),
    if (MobilePostSourceService.isSupportedPlatform)
      SettingsGroup(
        title: copy.mobileSourceGroupTitle,
        icon: Icons.devices_rounded,
        items: [
          SwitchModel(
            id: 'mobilePostSource',
            title: copy.mobileSourceTitle,
            subtitle: copy.mobileSourceDescription,
            icon: Icons.devices_rounded,
            getValue: (ref) =>
                ref.watch(mobilePostSourcePreferencesProvider).enabled,
            onChanged: (ref, value) => ref
                .read(mobilePostSourcePreferencesProvider.notifier)
                .setEnabled(value),
          ),
          ActionModel(
            id: 'mobilePostSourceModel',
            title: copy.mobileSourceModelTitle,
            subtitle: copy.mobileSourceModelDescription,
            icon: Icons.edit_rounded,
            getDynamicSubtitle: (ref) {
              final state = ref.watch(mobilePostSourcePreferencesProvider);
              final customModel = state.customModel;
              if (customModel != null) {
                return '${copy.mobileSourceCustomPrefix}: $customModel';
              }
              if (state.detecting) return copy.mobileSourceDetecting;
              final model = state.detectedInfo?.model;
              if (model == null || model.isEmpty) {
                return copy.mobileSourceUnavailable;
              }
              return '${copy.mobileSourceAutomaticPrefix}: $model';
            },
            onTap: (context, ref) {
              unawaited(_showMobileSourceModelDialog(context, ref, copy));
            },
          ),
        ],
      ),
    buildAccountQuickSwitcherAppearanceGroup(context),
  ];
}

Future<void> _showMobileSourceModelDialog(
  BuildContext context,
  WidgetRef ref,
  _CustomSettingsCopy copy,
) async {
  final state = ref.read(mobilePostSourcePreferencesProvider);
  final detectedModel = state.detectedInfo?.model;
  final controller = TextEditingController(
    text: state.customModel ?? detectedModel ?? '',
  );

  try {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy.mobileSourceModelDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(copy.mobileSourceModelDialogDescription),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              decoration: InputDecoration(
                hintText: detectedModel ?? copy.mobileSourceUnavailable,
              ),
            ),
          ],
        ),
        actions: [
          if (detectedModel != null && detectedModel.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: Text(copy.mobileSourceUseDetected),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(copy.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(copy.save),
          ),
        ],
      ),
    );

    if (result == null) return;
    await ref
        .read(mobilePostSourcePreferencesProvider.notifier)
        .setCustomModel(result);
  } finally {
    controller.dispose();
  }
}

class _CustomSettingsCopy {
  const _CustomSettingsCopy({
    required this.cacheGroupTitle,
    required this.preloadCacheTitle,
    required this.preloadCacheDescription,
    required this.clearPreloadCacheTitle,
    required this.clearPreloadCacheDescription,
    required this.preloadCacheCleared,
    required this.preloadCacheClearFailed,
    required this.readingGroupTitle,
    required this.quickReadingTitle,
    required this.quickReadingDescription,
    required this.mobileSourceGroupTitle,
    required this.mobileSourceTitle,
    required this.mobileSourceDescription,
    required this.mobileSourceModelTitle,
    required this.mobileSourceModelDescription,
    required this.mobileSourceAutomaticPrefix,
    required this.mobileSourceCustomPrefix,
    required this.mobileSourceDetecting,
    required this.mobileSourceUnavailable,
    required this.mobileSourceModelDialogTitle,
    required this.mobileSourceModelDialogDescription,
    required this.mobileSourceUseDetected,
    required this.cancel,
    required this.save,
  });

  final String cacheGroupTitle;
  final String preloadCacheTitle;
  final String preloadCacheDescription;
  final String clearPreloadCacheTitle;
  final String clearPreloadCacheDescription;
  final String preloadCacheCleared;
  final String preloadCacheClearFailed;
  final String readingGroupTitle;
  final String quickReadingTitle;
  final String quickReadingDescription;
  final String mobileSourceGroupTitle;
  final String mobileSourceTitle;
  final String mobileSourceDescription;
  final String mobileSourceModelTitle;
  final String mobileSourceModelDescription;
  final String mobileSourceAutomaticPrefix;
  final String mobileSourceCustomPrefix;
  final String mobileSourceDetecting;
  final String mobileSourceUnavailable;
  final String mobileSourceModelDialogTitle;
  final String mobileSourceModelDialogDescription;
  final String mobileSourceUseDetected;
  final String cancel;
  final String save;

  static _CustomSettingsCopy of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') return _en;
    if (locale.scriptCode?.toLowerCase() == 'hant' ||
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK' ||
        locale.countryCode == 'MO') {
      return _zhHant;
    }
    return _zhHans;
  }

  static const _zhHans = _CustomSettingsCopy(
    cacheGroupTitle: '实验性缓存',
    preloadCacheTitle: '预加载缓存（实验性）',
    preloadCacheDescription:
        '缓存首页 preload 最多 7 天并按账号独立存储；命中时跳过首页 preload 网络请求。关闭后停止读写，但不会自动删除已有缓存。',
    clearPreloadCacheTitle: '清理预加载缓存',
    clearPreloadCacheDescription: '一次清理所有账号独立保存的 preload cache。',
    preloadCacheCleared: '已清理所有账号的预加载缓存。',
    preloadCacheClearFailed: '清理预加载缓存失败。',
    readingGroupTitle: '阅读增强',
    quickReadingTitle: '快速阅读',
    quickReadingDescription: '进入话题时立即上报当前所有未读楼层；超过 2000 个楼层时按每批 2000 个分批发送。',
    mobileSourceGroupTitle: '发帖来源（实验性）',
    mobileSourceTitle: '发送设备型号（实验性）',
    mobileSourceDescription:
        '开启后，Android/iOS/Windows/macOS/Linux 的公开发帖与回复会按 Linux.do 当前协议发送 ios_device_name；Web 不发送。',
    mobileSourceModelTitle: '发送的设备型号',
    mobileSourceModelDescription: '可自定义；未设置时默认使用识别到的手机或电脑型号。',
    mobileSourceAutomaticPrefix: '自动',
    mobileSourceCustomPrefix: '自定义',
    mobileSourceDetecting: '正在识别本机设备型号…',
    mobileSourceUnavailable: '未识别到本机设备型号',
    mobileSourceModelDialogTitle: '自定义设备型号',
    mobileSourceModelDialogDescription:
        '默认使用识别到的手机或电脑型号。可以改成自定义文本；留空或点击“使用本机设备型号”会恢复自动识别。',
    mobileSourceUseDetected: '使用本机设备型号',
    cancel: '取消',
    save: '保存',
  );

  static const _zhHant = _CustomSettingsCopy(
    cacheGroupTitle: '實驗性快取',
    preloadCacheTitle: '預載入快取（實驗性）',
    preloadCacheDescription:
        '快取首頁 preload 最多 7 天並按帳號獨立儲存；命中時略過首頁 preload 網路請求。關閉後停止讀寫，但不會自動刪除既有快取。',
    clearPreloadCacheTitle: '清理預載入快取',
    clearPreloadCacheDescription: '一次清理所有帳號獨立保存的 preload cache。',
    preloadCacheCleared: '已清理所有帳號的預載入快取。',
    preloadCacheClearFailed: '清理預載入快取失敗。',
    readingGroupTitle: '閱讀增強',
    quickReadingTitle: '快速閱讀',
    quickReadingDescription: '進入話題時立即上報目前所有未讀樓層；超過 2000 個樓層時按每批 2000 個分批傳送。',
    mobileSourceGroupTitle: '發帖來源（實驗性）',
    mobileSourceTitle: '傳送裝置型號（實驗性）',
    mobileSourceDescription:
        '開啟後，Android/iOS/Windows/macOS/Linux 的公開發帖與回覆會依 Linux.do 目前協議傳送 ios_device_name；Web 不傳送。',
    mobileSourceModelTitle: '傳送的裝置型號',
    mobileSourceModelDescription: '可自訂；未設定時預設使用識別到的手機或電腦型號。',
    mobileSourceAutomaticPrefix: '自動',
    mobileSourceCustomPrefix: '自訂',
    mobileSourceDetecting: '正在識別本機裝置型號…',
    mobileSourceUnavailable: '未識別到本機裝置型號',
    mobileSourceModelDialogTitle: '自訂裝置型號',
    mobileSourceModelDialogDescription:
        '預設使用識別到的手機或電腦型號。可以改成自訂文字；留空或點擊「使用本機裝置型號」會恢復自動識別。',
    mobileSourceUseDetected: '使用本機裝置型號',
    cancel: '取消',
    save: '儲存',
  );

  static const _en = _CustomSettingsCopy(
    cacheGroupTitle: 'Experimental cache',
    preloadCacheTitle: 'Preload cache (experimental)',
    preloadCacheDescription: 'Caches the home preload for up to 7 days in an account-isolated store. A hit skips the preload home request. Disabling stops reads and writes without deleting existing cache.',
    clearPreloadCacheTitle: 'Clear preload cache',
    clearPreloadCacheDescription: 'Clears the independently stored preload cache for every account at once.',
    preloadCacheCleared: 'Preload cache cleared for all accounts.',
    preloadCacheClearFailed: 'Failed to clear preload cache.',
    readingGroupTitle: 'Reading enhancements',
    quickReadingTitle: 'Quick reading',
    quickReadingDescription: 'Immediately reports every currently unread post when entering a topic. More than 2,000 posts are sent in batches of 2,000.',
    mobileSourceGroupTitle: 'Post source (experimental)',
    mobileSourceTitle: 'Send device model (experimental)',
    mobileSourceDescription: 'When enabled, native Android, iOS, Windows, macOS, and Linux topics and replies send the device model through Linux.do\'s current ios_device_name field. Web never sends it.',
    mobileSourceModelTitle: 'Device model to send',
    mobileSourceModelDescription:
        'Customizable; defaults to the model detected on this device.',
    mobileSourceAutomaticPrefix: 'Automatic',
    mobileSourceCustomPrefix: 'Custom',
    mobileSourceDetecting: 'Detecting this device…',
    mobileSourceUnavailable: 'Device model unavailable',
    mobileSourceModelDialogTitle: 'Custom device model',
    mobileSourceModelDialogDescription: 'The detected local model is used by default. Enter a custom value, or leave it empty to return to automatic detection.',
    mobileSourceUseDetected: 'Use detected model',
    cancel: 'Cancel',
    save: 'Save',
  );
}
