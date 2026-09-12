import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../../providers/preload_cache_preferences.dart';
import '../../providers/quick_reading_preferences.dart';
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
    buildAccountQuickSwitcherAppearanceGroup(context),
  ];
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
  );

  static const _en = _CustomSettingsCopy(
    cacheGroupTitle: 'Experimental cache',
    preloadCacheTitle: 'Preload cache (experimental)',
    preloadCacheDescription:
        'Caches the home preload for up to 7 days in an account-isolated store. A hit skips the preload home request. Disabling stops reads and writes without deleting existing cache.',
    clearPreloadCacheTitle: 'Clear preload cache',
    clearPreloadCacheDescription:
        'Clears the independently stored preload cache for every account at once.',
    preloadCacheCleared: 'Preload cache cleared for all accounts.',
    preloadCacheClearFailed: 'Failed to clear preload cache.',
    readingGroupTitle: 'Reading enhancements',
    quickReadingTitle: 'Quick reading',
    quickReadingDescription:
        'Immediately reports every currently unread post when entering a topic. More than 2,000 posts are sent in batches of 2,000.',
  );
}
