import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32_registry/win32_registry.dart';

/// 当前设备可随公开帖子发送的来源信息。
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

/// Linux.do 设备型号识别与未来发送链路的本地数据服务。
///
/// Linux.do 帖子响应中的 `via_ios_app` / `ios_device_name` 是官方 iOS
/// 认证链路生成的服务端可信来源信息。普通 Discourse `/posts.json` 请求
/// 不能通过同名表单参数伪造，因此本服务当前只负责本机型号识别与预配置，
/// 不向公开发帖接口注入来源字段。
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
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
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

      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        final modelName = info.modelName.trim();
        final modelIdentifier = info.model.trim();
        return MobilePostSourceInfo(
          platform: 'macos',
          brand: 'Apple',
          model: modelName.isNotEmpty ? modelName : modelIdentifier,
        );
      }

      if (Platform.isWindows) {
        final hardware = _readWindowsHardwareInfo();
        final fallback = await plugin.windowsInfo;
        return MobilePostSourceInfo(
          platform: 'windows',
          brand: hardware.brand,
          model: hardware.model ?? fallback.computerName.trim(),
        );
      }

      if (Platform.isLinux) {
        final hardware = await _readLinuxHardwareInfo();
        return MobilePostSourceInfo(
          platform: 'linux',
          brand: hardware.brand,
          model: hardware.model ?? '',
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

  /// 官方 iOS 来源字段需要经过 Linux.do 的受信任认证链路。
  ///
  /// 保留显式能力标记，防止后续调用方再次把 serializer 输出字段当成
  /// /posts.json 的普通客户端参数。
  static bool get canSendVerifiedPostSource => false;

  static _DesktopHardwareInfo _readWindowsHardwareInfo() {
    RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.localMachine,
        path: r'HARDWARE\DESCRIPTION\System\BIOS',
      );
      return _DesktopHardwareInfo(
        brand: _normalizeHardwareText(
          key.getStringValue('SystemManufacturer'),
        ),
        model: _normalizeHardwareText(
          key.getStringValue('SystemProductName'),
        ),
      );
    } catch (_) {
      return const _DesktopHardwareInfo();
    } finally {
      key?.close();
    }
  }

  static Future<_DesktopHardwareInfo> _readLinuxHardwareInfo() async {
    final brand = await _readFirstNonEmptyFile(const [
      '/sys/devices/virtual/dmi/id/sys_vendor',
      '/sys/class/dmi/id/sys_vendor',
    ]);
    final model = await _readFirstNonEmptyFile(const [
      '/sys/devices/virtual/dmi/id/product_name',
      '/sys/class/dmi/id/product_name',
      '/sys/firmware/devicetree/base/model',
    ]);
    return _DesktopHardwareInfo(brand: brand, model: model);
  }

  static Future<String?> _readFirstNonEmptyFile(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final value = _normalizeHardwareText(await file.readAsString());
        if (value != null) return value;
      } catch (_) {
        // 某些 sysfs 节点在沙箱/容器中不可读，继续尝试下一个候选。
      }
    }
    return null;
  }

  static String? _normalizeHardwareText(String? value) {
    if (value == null) return null;
    final normalized = value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;
    final lower = normalized.toLowerCase();
    const placeholders = {
      'system product name',
      'default string',
      'to be filled by o.e.m.',
      'to be filled by oem',
      'not specified',
      'unknown',
      'none',
    };
    return placeholders.contains(lower) ? null : normalized;
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

class _DesktopHardwareInfo {
  const _DesktopHardwareInfo({this.brand, this.model});

  final String? brand;
  final String? model;
}
