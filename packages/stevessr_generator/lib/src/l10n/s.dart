import 'package:flutter/widgets.dart';

/// Standalone generator localization facade. UI strings intentionally live in this package.
class GeneratorStrings {
  const GeneratorStrings();
  String get imageLoadFailed => '图片加载失败';
  String get imageTooLarge => '图片过大';
  String get renderFailed => '生成失败';
  String get title => '表情包生成器';
  String get description => '编辑文字与角色，拖动预览元素调整布局。';
  String get text => '文字';
  String get character => '角色';
  String get originalCharacter => '默认';
  String get expression => '表情';
  String get bubble => '气泡';
  String get format => '格式';
  String get png => 'PNG';
  String get webp => 'WebP';
  String get avif => 'AVIF';
  String get jpeg => 'JPEG';
  String get svg => 'SVG';
  String get quality => '质量';
  String get width => '宽度';
  String get height => '高度';
  String get transparent => '透明背景';
  String get background => '背景';
  String get bubbleFill => '气泡填充';
  String get bubbleStroke => '气泡描边';
  String get textColor => '文字颜色';
  String get tail => '气泡尾巴';
  String get left => '左';
  String get right => '右';
  String get none => '无';
  String get font => '字体';
  String get sans => '无衬线';
  String get serif => '衬线';
  String get mono => '等宽';
  String get rounded => '圆体';
  String get align => '对齐';
  String get center => '居中';
  String get fontMin => '最小字号';
  String get fontMax => '最大字号';
  String get lineHeight => '行高';
  String get padding => '内边距';
  String get insert => '生成并插入';
  String get save => '保存';
  String get share => '分享';
  String get rendering => '正在生成…';
  String get bubbleContent => '气泡内容';
  String get bubbleImage => '图片';
  String get chooseImage => '选择图片';
  String get replaceImage => '更换图片';
  String get removeImage => '移除图片';
  String get position => '位置与尺寸';
  String get bubbleX => '气泡 X';
  String get bubbleY => '气泡 Y';
  String get bubbleWidth => '气泡宽度';
  String get bubbleHeight => '气泡高度';
}

extension GeneratorL10n on BuildContext {
  GeneratorStrings get l10n => const GeneratorStrings();
}
