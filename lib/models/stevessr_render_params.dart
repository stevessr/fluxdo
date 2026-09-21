import 'dart:typed_data';
import 'dart:ui';

/// StevesSR 可用的角色表情。
enum StevessrExpression {
  neutral,
  pout,
  smug,
  surprised,
  happy,
  cry,
  angry,
  embarrassed,
  sleepy,
  love,
  laughing,
  wink,
  confused,
  thinking,
  panic,
  pleading,
  apologetic,
  celebrating,
  dizzy,
  bored,
  scared,
  hungry,
  grateful,
}

/// StevesSR 可用的气泡造型。
enum StevessrBubble { thought, speech, cloud, shout, rounded, caption }

/// 生成器可选的角色立绘。
///
/// [StevessrCharacter.original] 渲染 `assets/images/avater/stevessr/` 下的表情
/// 素材（此时由 [StevessrExpression] 决定）；其余值渲染
/// `assets/images/avater/` 下对应目录的角色立绘，表情维度不生效。
enum StevessrCharacter {
  original,
  reimu,
  marisa,
  flandre,
  remilia,
  sakuya,
  patchouli,
  koishi,
  satori,
  okuu,
  okuuRin,
  yuyuko,
  youmu,
  yukari,
  cirno,
  sanae,
  suika,
  suwako,
  tenshi,
  kokoro,
  kaguya,
  einin,
  aya,
  akyuu,
  renko,
  sumireko,
  maribel,
  keine,
  deepseek,
  blueArchive01,
  blueArchive02,
  blueArchive03,
  blueArchive04,
  blueArchive05,
  blueArchive06,
  witchJudgmentEma,
  witchJudgmentHiro,
  witchJudgmentAnAn,
  witchJudgmentNoah,
  witchJudgmentLeia,
  witchJudgmentMiria,
  witchJudgmentMargo,
  witchJudgmentNanoka,
  witchJudgmentAlisa,
  witchJudgmentSherry,
  witchJudgmentHanna,
  witchJudgmentKoko,
  witchJudgmentMeruru,
}

extension StevessrCharacterKey on StevessrCharacter {
  /// 资源文件名（不含扩展名）。
  String get key => switch (this) {
    StevessrCharacter.original => '',
    StevessrCharacter.okuuRin => 'okuu_rin',
    StevessrCharacter.blueArchive01 => 'blue_archive_01',
    StevessrCharacter.blueArchive02 => 'blue_archive_02',
    StevessrCharacter.blueArchive03 => 'blue_archive_03',
    StevessrCharacter.blueArchive04 => 'blue_archive_04',
    StevessrCharacter.blueArchive05 => 'blue_archive_05',
    StevessrCharacter.blueArchive06 => 'blue_archive_06',
    StevessrCharacter.witchJudgmentEma => '樱羽艾玛',
    StevessrCharacter.witchJudgmentHiro => '二阶堂希罗',
    StevessrCharacter.witchJudgmentAnAn => '夏目安安',
    StevessrCharacter.witchJudgmentNoah => '城崎诺亚',
    StevessrCharacter.witchJudgmentLeia => '莲见蕾雅',
    StevessrCharacter.witchJudgmentMiria => '佐伯米莉亚',
    StevessrCharacter.witchJudgmentMargo => '宝生玛格',
    StevessrCharacter.witchJudgmentNanoka => '黑部奈叶香',
    StevessrCharacter.witchJudgmentAlisa => '紫藤亚里沙',
    StevessrCharacter.witchJudgmentSherry => '橘雪莉',
    StevessrCharacter.witchJudgmentHanna => '远野汉娜',
    StevessrCharacter.witchJudgmentKoko => '泽渡可可',
    StevessrCharacter.witchJudgmentMeruru => '冰上梅露露',
    _ => name,
  };

  /// 是否使用 StevesSR 表情素材。
  bool get supportsExpression => this == StevessrCharacter.original;

  /// 资源路径（相对于 `assets/images/avater/`）。
  String assetPath({StevessrExpression? expression}) => switch (this) {
    StevessrCharacter.original =>
      'stevessr/${(expression ?? StevessrExpression.neutral).key}.webp',
    StevessrCharacter.deepseek => 'llm/deepseek.webp',
    StevessrCharacter.blueArchive01 ||
    StevessrCharacter.blueArchive02 ||
    StevessrCharacter.blueArchive03 ||
    StevessrCharacter.blueArchive04 ||
    StevessrCharacter.blueArchive05 ||
    StevessrCharacter.blueArchive06 => 'blue_archive/$key.webp',
    StevessrCharacter.witchJudgmentEma ||
    StevessrCharacter.witchJudgmentHiro ||
    StevessrCharacter.witchJudgmentAnAn ||
    StevessrCharacter.witchJudgmentNoah ||
    StevessrCharacter.witchJudgmentLeia ||
    StevessrCharacter.witchJudgmentMiria ||
    StevessrCharacter.witchJudgmentMargo ||
    StevessrCharacter.witchJudgmentNanoka ||
    StevessrCharacter.witchJudgmentAlisa ||
    StevessrCharacter.witchJudgmentSherry ||
    StevessrCharacter.witchJudgmentHanna ||
    StevessrCharacter.witchJudgmentKoko ||
    StevessrCharacter.witchJudgmentMeruru => 'witch_judgment/$key.webp',
    _ => 'touhou/$key.webp',
  };

  /// 下拉列表显示名；东方角色用官方中文译名。
  String get displayName => switch (this) {
    StevessrCharacter.original => '',
    StevessrCharacter.reimu => '博丽灵梦',
    StevessrCharacter.marisa => '雾雨魔理沙',
    StevessrCharacter.flandre => '芙兰朵露·斯卡蕾特',
    StevessrCharacter.remilia => '蕾米莉亚·斯卡蕾特',
    StevessrCharacter.sakuya => '十六夜咲夜',
    StevessrCharacter.patchouli => '帕秋莉·诺蕾姬',
    StevessrCharacter.koishi => '古明地恋',
    StevessrCharacter.satori => '古明地觉',
    StevessrCharacter.okuu => '灵乌路空',
    StevessrCharacter.okuuRin => '火焰猫燐',
    StevessrCharacter.yuyuko => '西行寺幽幽子',
    StevessrCharacter.youmu => '魂魄妖梦',
    StevessrCharacter.yukari => '八云紫',
    StevessrCharacter.cirno => '琪露诺',
    StevessrCharacter.sanae => '东风谷早苗',
    StevessrCharacter.suika => '伊吹萃香',
    StevessrCharacter.suwako => '洩矢诹访子',
    StevessrCharacter.tenshi => '比那名居天子',
    StevessrCharacter.kokoro => '秦心',
    StevessrCharacter.kaguya => '蓬莱山辉夜',
    StevessrCharacter.einin => '八意永琳',
    StevessrCharacter.aya => '射命丸文',
    StevessrCharacter.akyuu => '稗田阿求',
    StevessrCharacter.renko => '宇佐见莲子',
    StevessrCharacter.sumireko => '宇佐见堇子',
    StevessrCharacter.maribel => '玛艾露贝莉·赫恩',
    StevessrCharacter.keine => '上白泽慧音',
    StevessrCharacter.deepseek => '鲸鲸子',
    StevessrCharacter.blueArchive01 => '碧蓝档案 01',
    StevessrCharacter.blueArchive02 => '碧蓝档案 02',
    StevessrCharacter.blueArchive03 => '碧蓝档案 03',
    StevessrCharacter.blueArchive04 => '碧蓝档案 04',
    StevessrCharacter.blueArchive05 => '碧蓝档案 05',
    StevessrCharacter.blueArchive06 => '碧蓝档案 06',
    StevessrCharacter.witchJudgmentEma => '樱羽艾玛',
    StevessrCharacter.witchJudgmentHiro => '二阶堂希罗',
    StevessrCharacter.witchJudgmentAnAn => '夏目安安',
    StevessrCharacter.witchJudgmentNoah => '城崎诺亚',
    StevessrCharacter.witchJudgmentLeia => '莲见蕾雅',
    StevessrCharacter.witchJudgmentMiria => '佐伯米莉亚',
    StevessrCharacter.witchJudgmentMargo => '宝生玛格',
    StevessrCharacter.witchJudgmentNanoka => '黑部奈叶香',
    StevessrCharacter.witchJudgmentAlisa => '紫藤亚里沙',
    StevessrCharacter.witchJudgmentSherry => '橘雪莉',
    StevessrCharacter.witchJudgmentHanna => '远野汉娜',
    StevessrCharacter.witchJudgmentKoko => '泽渡可可',
    StevessrCharacter.witchJudgmentMeruru => '冰上梅露露',
  };
}

enum StevessrFont { sans, serif, mono, rounded }

enum StevessrTextAlign { left, center, right }

enum StevessrTail { left, right, none }

/// 气泡内容类型。
enum StevessrBubbleContent { text, image }

enum StevessrFormat { png, webp, avif, jpeg, svg }

extension StevessrExpressionKey on StevessrExpression {
  String get key => name;
}

extension StevessrBubbleKey on StevessrBubble {
  String get key => name;
}

extension StevessrFontKey on StevessrFont {
  String get key => name;
}

extension StevessrTextAlignKey on StevessrTextAlign {
  String get key => name;
}

extension StevessrTailKey on StevessrTail {
  String get key => name;
}

extension StevessrBubbleContentKey on StevessrBubbleContent {
  String get key => name;
}

extension StevessrFormatKey on StevessrFormat {
  String get key => name;
}

/// 源 API 中用于描述气泡和角色的位置矩形。
class StevessrRect {
  const StevessrRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  StevessrRect copyWith({double? x, double? y, double? width, double? height}) {
    return StevessrRect(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StevessrRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// StevesSR 生成参数。
///
/// 参数范围与源项目 `parseRenderParams` 保持一致，页面控件只修改这个模型，
/// 绘制器和导出器不直接依赖表单状态。
class StevessrRenderParams {
  const StevessrRenderParams({
    required this.text,
    required this.expression,
    this.character = StevessrCharacter.original,
    required this.bubble,
    required this.format,
    required this.width,
    required this.height,
    required this.transparent,
    required this.background,
    required this.bubbleFill,
    required this.bubbleStroke,
    required this.bubbleStrokeWidth,
    required this.textColor,
    required this.font,
    required this.fontWeight,
    required this.fontMin,
    required this.fontMax,
    required this.lineHeight,
    required this.padding,
    required this.align,
    required this.tail,
    this.bubbleContent = StevessrBubbleContent.text,
    this.bubbleImageBytes,
    this.bubbleImageMimeType,
    required this.quality,
    required this.bubbleRect,
    required this.characterRect,
  });

  factory StevessrRenderParams.defaults() {
    return const StevessrRenderParams(
      text: '今天也要\n可可爱爱地\n摸鱼一下！',
      expression: StevessrExpression.neutral,
      bubble: StevessrBubble.thought,
      format: StevessrFormat.png,
      width: 1254,
      height: 1254,
      transparent: false,
      background: Color(0xffffffff),
      bubbleFill: Color(0xffffffff),
      bubbleStroke: Color(0xff071716),
      bubbleStrokeWidth: 15.048,
      textColor: Color(0xff111111),
      font: StevessrFont.sans,
      fontWeight: 600,
      fontMin: 23,
      fontMax: 71,
      lineHeight: 1.15,
      padding: 45,
      align: StevessrTextAlign.center,
      tail: StevessrTail.right,
      quality: 90,
      bubbleRect: StevessrRect(x: 65, y: 66, width: 665, height: 385),
      characterRect: StevessrRect(x: 464, y: 451, width: 803, height: 803),
    );
  }

  final String text;
  final StevessrExpression expression;
  final StevessrCharacter character;
  final StevessrBubble bubble;
  final StevessrFormat format;
  final int width;
  final int height;
  final bool transparent;
  final Color background;
  final Color bubbleFill;
  final Color bubbleStroke;
  final double bubbleStrokeWidth;
  final Color textColor;
  final StevessrFont font;
  final int fontWeight;
  final int fontMin;
  final int fontMax;
  final double lineHeight;
  final double padding;
  final StevessrTextAlign align;
  final StevessrTail tail;
  final StevessrBubbleContent bubbleContent;
  final Uint8List? bubbleImageBytes;
  final String? bubbleImageMimeType;
  final int quality;
  final StevessrRect bubbleRect;
  final StevessrRect characterRect;

  /// 当前是否使用气泡图片作为内容。
  bool get usesBubbleImage =>
      bubbleContent == StevessrBubbleContent.image &&
      bubbleImageBytes != null &&
      bubbleImageBytes!.isNotEmpty;

  /// 限制导出范围，同时允许 128/256 等常见表情尺寸。
  StevessrRenderParams normalized() {
    final safeWidth = width.clamp(128, 2048).toInt();
    final safeHeight = height.clamp(128, 2048).toInt();
    final defaultBubble = StevessrRect(
      x: (safeWidth * .052).roundToDouble(),
      y: (safeHeight * .053).roundToDouble(),
      width: (safeWidth * .530).roundToDouble(),
      height: (safeHeight * .307).roundToDouble(),
    );
    final defaultCharacter = StevessrRect(
      x: (safeWidth * .37).roundToDouble(),
      y: (safeHeight * .36).roundToDouble(),
      width: (safeWidth * .64).roundToDouble(),
      height: (safeHeight * .64).roundToDouble(),
    );
    final maxFont = fontMax.clamp(12, 220).toInt();
    final minFont = fontMin.clamp(8, maxFont).toInt();

    final imageBytes = bubbleImageBytes;
    return StevessrRenderParams(
      text: _truncateText(text),
      expression: expression,
      character: character,
      bubble: bubble,
      format: format,
      width: safeWidth,
      height: safeHeight,
      transparent: transparent,
      background: background,
      bubbleFill: bubbleFill,
      bubbleStroke: bubbleStroke,
      bubbleStrokeWidth: bubbleStrokeWidth.clamp(1, 60).toDouble(),
      textColor: textColor,
      font: font,
      fontWeight: fontWeight.clamp(100, 900).toInt(),
      fontMin: minFont,
      fontMax: maxFont,
      lineHeight: lineHeight.clamp(.8, 2.0).toDouble(),
      padding: padding.clamp(0, 180).toDouble(),
      align: align,
      tail: tail,
      bubbleContent: imageBytes != null && imageBytes.isNotEmpty
          ? bubbleContent
          : StevessrBubbleContent.text,
      bubbleImageBytes: imageBytes,
      bubbleImageMimeType: imageBytes != null && imageBytes.isNotEmpty
          ? bubbleImageMimeType
          : null,
      quality: quality.clamp(20, 100).toInt(),
      bubbleRect: _normalizeBubble(
        bubbleRect,
        defaultBubble,
        safeWidth,
        safeHeight,
      ),
      characterRect: _normalizeCharacter(
        characterRect,
        defaultCharacter,
        safeWidth,
        safeHeight,
      ),
    );
  }

  StevessrRect _normalizeBubble(
    StevessrRect value,
    StevessrRect fallback,
    int safeWidth,
    int safeHeight,
  ) {
    return StevessrRect(
      x: value.x.isFinite
          ? value.x.clamp(-safeWidth, safeWidth * 2).toDouble()
          : fallback.x,
      y: value.y.isFinite
          ? value.y.clamp(-safeHeight, safeHeight * 2).toDouble()
          : fallback.y,
      width: value.width.isFinite
          ? value.width.clamp(32, safeWidth * 1.5).toDouble()
          : fallback.width,
      height: value.height.isFinite
          ? value.height.clamp(32, safeHeight * 1.5).toDouble()
          : fallback.height,
    );
  }

  StevessrRect _normalizeCharacter(
    StevessrRect value,
    StevessrRect fallback,
    int safeWidth,
    int safeHeight,
  ) {
    return StevessrRect(
      x: value.x.isFinite
          ? value.x.clamp(-safeWidth, safeWidth * 2).toDouble()
          : fallback.x,
      y: value.y.isFinite
          ? value.y.clamp(-safeHeight, safeHeight * 2).toDouble()
          : fallback.y,
      width: value.width.isFinite
          ? value.width.clamp(24, safeWidth * 2).toDouble()
          : fallback.width,
      height: value.height.isFinite
          ? value.height.clamp(24, safeHeight * 2).toDouble()
          : fallback.height,
    );
  }

  StevessrRenderParams copyWith({
    String? text,
    StevessrExpression? expression,
    StevessrCharacter? character,
    StevessrBubble? bubble,
    StevessrFormat? format,
    int? width,
    int? height,
    bool? transparent,
    Color? background,
    Color? bubbleFill,
    Color? bubbleStroke,
    double? bubbleStrokeWidth,
    Color? textColor,
    StevessrFont? font,
    int? fontWeight,
    int? fontMin,
    int? fontMax,
    double? lineHeight,
    double? padding,
    StevessrTextAlign? align,
    StevessrTail? tail,
    StevessrBubbleContent? bubbleContent,
    Uint8List? bubbleImageBytes,
    String? bubbleImageMimeType,
    bool clearBubbleImage = false,
    int? quality,
    StevessrRect? bubbleRect,
    StevessrRect? characterRect,
  }) {
    return StevessrRenderParams(
      text: text ?? this.text,
      expression: expression ?? this.expression,
      character: character ?? this.character,
      bubble: bubble ?? this.bubble,
      format: format ?? this.format,
      width: width ?? this.width,
      height: height ?? this.height,
      transparent: transparent ?? this.transparent,
      background: background ?? this.background,
      bubbleFill: bubbleFill ?? this.bubbleFill,
      bubbleStroke: bubbleStroke ?? this.bubbleStroke,
      bubbleStrokeWidth: bubbleStrokeWidth ?? this.bubbleStrokeWidth,
      textColor: textColor ?? this.textColor,
      font: font ?? this.font,
      fontWeight: fontWeight ?? this.fontWeight,
      fontMin: fontMin ?? this.fontMin,
      fontMax: fontMax ?? this.fontMax,
      lineHeight: lineHeight ?? this.lineHeight,
      padding: padding ?? this.padding,
      align: align ?? this.align,
      tail: tail ?? this.tail,
      bubbleContent: bubbleContent ?? this.bubbleContent,
      bubbleImageBytes: clearBubbleImage
          ? null
          : bubbleImageBytes ?? this.bubbleImageBytes,
      bubbleImageMimeType: clearBubbleImage
          ? null
          : bubbleImageMimeType ?? this.bubbleImageMimeType,
      quality: quality ?? this.quality,
      bubbleRect: bubbleRect ?? this.bubbleRect,
      characterRect: characterRect ?? this.characterRect,
    ).normalized();
  }

  static String _truncateText(String value) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= 500) return value;
    return String.fromCharCodes(runes.take(500));
  }
}
