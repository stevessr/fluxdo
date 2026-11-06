/// 一个可选维度（baoyu 多维组合的一维）
///
/// 比如「画风」维度有「水彩 / 像素 / 手绘」三个选项。点击 preset 时弹出维度
/// 选择面板，用户选完后把每个维度的 [DimensionOption.promptFragment] 拼接
/// 到 preset 的 promptTemplate 后面。
class PromptDimension {
  const PromptDimension({
    required this.id,
    required this.label,
    required this.options,
    this.required = false,
  });

  /// 维度 ID（在同一 preset 内唯一），如 'palette' / 'rendering'
  final String id;

  /// 维度名（已解析的本地化文本），如「色彩」「画风」
  final String label;

  /// 选项列表
  final List<DimensionOption> options;

  /// 是否必选。false 时用户可以不选（不拼任何 fragment）
  final bool required;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'required': required,
    'options': options.map((e) => e.toJson()).toList(),
  };

  factory PromptDimension.fromJson(Map<String, dynamic> json) {
    return PromptDimension(
      id: json['id'] as String,
      label: json['label'] as String,
      required: json['required'] as bool? ?? false,
      options:
          (json['options'] as List<dynamic>?)
              ?.map((e) => DimensionOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// 维度的一个选项
class DimensionOption {
  const DimensionOption({
    required this.value,
    required this.label,
    required this.promptFragment,
    this.iconRaw,
  });

  /// 选项值（持久化时存这个），如 'warm'
  final String value;

  /// 显示名（已解析的本地化文本），如「暖色」
  final String label;

  /// 拼接到 prompt 末尾的描述（已解析的本地化文本）
  ///
  /// 应当是一段自然语言修饰词，让最终 prompt 读起来连贯。
  /// 如：「使用暖色调（橘红、米黄、咖啡）作为主色」
  final String promptFragment;

  /// 可选可视化图标（emoji 或 Material icon name）
  final String? iconRaw;

  Map<String, dynamic> toJson() => {
    'value': value,
    'label': label,
    'promptFragment': promptFragment,
    if (iconRaw != null) 'iconRaw': iconRaw,
  };

  factory DimensionOption.fromJson(Map<String, dynamic> json) {
    return DimensionOption(
      value: json['value'] as String,
      label: json['label'] as String,
      promptFragment: json['promptFragment'] as String,
      iconRaw: json['iconRaw'] as String?,
    );
  }
}
