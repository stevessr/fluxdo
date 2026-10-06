import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 当前移动设备可随公开帖子发送的来源信息。
class MobilePostSourceInfo {
  const MobilePostSourceInfo({
    required this.platform,
    required this.brand,
    required this.model,
  });

  final String platform;
  final String? brand;
  final String model;
}

/// Linux.do 移动端发帖来源实验功能。
///
/// 服务端识别 `mobile_source_platform` / `mobile_source_brand` /
/// `mobile_source_model`。出于隐私考虑默认关闭，且仅 Android / iOS
/// 的公开发帖链路会调用本服务；桌面端和 Web 始终返回空字段。
class MobilePostSourceService {
  MobilePostSourceService._();

  static const enabledKey = 'pref_mobile_post_source_enabled';
  static const customModelKey = 'pref_mobile_post_source_custom_model';

  static const Set<String> _androidSubBrands = {
    'iqoo',
    'redmi',
    'poco',
    'realme',
    'honor',
    'nothing',
  };

  static Future<MobilePostSourceInfo?>? _deviceInfoFuture;

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 只读一次设备信息，避免每次发送都触发 platform channel。
  static Future<MobilePostSourceInfo?> detectDeviceInfo() {
    return _deviceInfoFuture ??= _readDeviceInfo();
  }

  static Future<MobilePostSourceInfo?> _readDeviceInfo() async {
    if (!isSupportedPlatform) return null;

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return MobilePostSourceInfo(
          platform: 'android',
          brand: _resolveAndroidBrand(
            manufacturer: info.manufacturer,
            brand: info.brand,
            model: info.model,
            device: info.device,
            product: info.product,
          ),
          model: info.model.trim(),
        );
      }

      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final machine = info.utsname.machine.trim();
        final fallback = info.model.trim();
        return MobilePostSourceInfo(
          platform: 'ios',
          brand: 'Apple',
          model: machine.isNotEmpty ? machine : fallback,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[MobilePostSource] Failed to detect device model: '
        '$error\n$stackTrace',
      );
    }

    return null;
  }

  static String? normalizeCustomModel(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }

  /// 纯函数版本，便于测试协议字段及自定义型号覆盖行为。
  static Map<String, String> buildFields({
    required MobilePostSourceInfo info,
    String? customModel,
  }) {
    final result = <String, String>{};
    final platform = info.platform.trim();
    final brand = info.brand?.trim();
    final model = normalizeCustomModel(customModel) ??
        normalizeCustomModel(info.model);

    if (platform.isNotEmpty) {
      result['mobile_source_platform'] = platform;
    }
    if (brand != null && brand.isNotEmpty) {
      result['mobile_source_brand'] = brand;
    }
    if (model != null) {
      result['mobile_source_model'] = model;
    }
    return result;
  }

  /// 根据本机设置构造公开发帖附加字段。
  ///
  /// 默认关闭；自定义型号为空时回退到设备识别型号。
  static Future<Map<String, String>> requestFieldsForCurrentDevice() async {
    if (!isSupportedPlatform) return const <String, String>{};

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(enabledKey) ?? false)) {
      return const <String, String>{};
    }

    final info = await detectDeviceInfo();
    if (info == null) return const <String, String>{};

    return buildFields(
      info: info,
      customModel: prefs.getString(customModelKey),
    );
  }

  static String? _resolveAndroidBrand({
    required String manufacturer,
    required String brand,
    required String model,
    required String device,
    required String product,
  }) {
    final candidates = [brand, manufacturer, model, device, product]
        .map(_normalizeDeviceHint)
        .join('\n');
    for (final subBrand in _androidSubBrands) {
      if (candidates.contains(subBrand)) return subBrand;
    }

    final normalizedManufacturer = manufacturer.trim();
    if (normalizedManufacturer.isNotEmpty) return normalizedManufacturer;
    final normalizedBrand = brand.trim();
    return normalizedBrand.isEmpty ? null : normalizedBrand;
  }

  static String _normalizeDeviceHint(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
