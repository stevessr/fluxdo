# 角色表情与差分资产（StevesSR / Claude / Deepseek）

## 制作源稿

- Claude 的原始 PNG 保留在 `llm/claude/original.png`，默认主图已转为无损 WebP，保留尺寸和透明通道。
- Claude / Deepseek 各有 `neutral.webp` 和 `happy.webp`、`surprised.webp`、`love.webp` 三份完整表情源稿。
- 源稿位于 `tool/`，**不会被 Flutter 打包**。AI 只制作嘴部/脸颊表情；导入时限制为原图的下半脸局部，羽化边缘，锁定其余像素，避免头发、衣服和轮廓漂移。
- 如需更新表情，可用内置 image_gen 编辑主图，再执行：

  ```sh
  dart tool/import_avatar_expression.dart claude happy /path/to/edited.png
  ```

  只有制作源稿的导入步骤需要 ImageMagick；正常构建只使用项目已有的 Dart `image` / `crypto` 依赖，无额外 Python 或系统图像工具依赖。

## 编译前生成

```sh
dart tool/gen_avatar_deltas.dart
dart tool/gen_avatar_deltas.dart --check
```

`project_prep.dart app/test` 自动执行生成，所以 `just build/run/test`、`tool/flutterw.dart` 和现有发布 CI 都会在编译前更新角色资产。生成产物已加入 `.gitignore`，仓库只跟踪源稿、生成器和目录占位。全新检出后请先 `dart tool/project_prep.dart test`（或 `app`），或直接用 `just build/run/test`；绕过包装器执行原生 `flutter build/test` 前必须手动生成。

最终 `assets/images/avater/llm/` 和 `stevessr/` 只包含：

- 每个角色一张主图 WebP；
- 每个非默认表情一个最小变化矩形（LLM 自动选择实际更小的 PNG / 无损 WebP，StevesSR 用无损 WebP；都是 RGBA 替换差分）；
- `manifest.json` 中的尺寸、差分位置与资源名。

差分必须按 RGBA **替换**对应区域，而不是透明叠加，才能正确还原删除或变透明的像素。预览和 SVG 导出共用还原服务；位图导出在截图前等待差分加载和绘制。默认主图仍走原有 `Image.asset`，其他无表情角色资源保持不变。运行时最多缓存最近 8 份还原结果，避免 23 种大图常驻。

StevesSR 的规范源稿位于 `tool/avatar_sources/stevessr/`：一张完整 `neutral.webp` 主图、22 张裁切后的无损差分 WebP，以及 `source.json`（差分位置、原稿可见 RGBA 的 SHA-256）。这些小矩形是可维护的源资产，不是打包目录的生成副本。原有完整图片保留在本地 `tool/avatar_originals/stevessr/`，该备份已忽略；原图也可从本次迁移前的 Git 历史恢复。

新增/重制 StevesSR 源稿时，把完整的 23 张 WebP 放到一个非打包目录，再运行：

```sh
dart tool/pack_stevessr_sources.dart /path/to/full-expressions
dart tool/optimize_avatar_bases.dart
dart tool/gen_avatar_deltas.dart
```

源稿制作器需要 ImageMagick，以高压缩的无损模式编码差分。日常本地/CI 构建只依赖 Dart，直接从规范源稿产生打包用主图、差分及清单，不需要重新安装编码工具或重新编码。这样避免纯 Dart 重编码大范围差分造成体积反增。保留原有所有可见像素、透明度、画布尺寸和 23 项表情；由于这些源稿的头发、衣服、姿势、纹理也存在大量变化，无损差分区域可能覆盖大部分角色，压缩收益必须以生成器报告为准，不能套用 LLM 的 72.4%。生成器不以节省空间为由裁去这些变化。

LLM 输入和输出使用 SHA-256 指纹，日常构建在未变化时跳过重新编码，`--check` 强制重算验证；StevesSR 验证规范源稿与生成副本的一致性。生成器也清理已移除表情的陈旧产物。

## 无损优化与画质边界

`dart tool/optimize_avatar_bases.dart` 在源稿制作阶段尝试高压缩的无损 WebP 主图编码；逐像素验证尺寸、所有可见 RGB 和完整 alpha 不变，只有更小才替换。这个可选维护工具需要 ImageMagick，日常编译不调用它。追加 `--all-avatars` 可同时无损优化东方、碧蓝档案、魔女审判的静态头像；两个编码进程并行，每张通过校验且更小才写入。

`test/fixtures/avatar_rgba_hashes.json` 保存这 46 张静态头像在提交 `0e95dfa5` 中的原始尺寸和可见 RGBA 哈希；`test/services/avatar_lossless_assets_test.dart` 使用独立基准防止压缩过程意外改变画面或透明度。基准不会由压缩器自动更新。

LLM 差分生成器同时尝试 PNG 与无损 WebP，并根据实际编码长度选更小的一份；编译期仍只依赖 Dart。不要将“无损 WebP 编码器”与 near-lossless 预处理混为一谈：near-lossless 仍可能修改原像素或透明边缘。高质量有损 WebP 只能在接受画质变化后单独采用，不能通过修改原稿验证哈希来冒充无损。

## 生成提示词

使用内置 `image_gen`，两位角色各执行以下三种编辑：保持原图尺寸、姿势、头发、眼睛、服装、透明背景和绘画风格，仅修改两眼下方原本空白的脸部，不加文字或水印。

- `happy`：开心张嘴微笑，露出小粉色舌头。
- `surprised`：小圆形 O 型惊讶嘴。
- `love`：甜美微笑，嘴巴两侧加桃粉色小爱心腮红。

## 验证

`test/services/stevessr_character_assets_test.dart` 逐像素验证全部 28 种非默认表情：LLM 与完整源稿比较，StevesSR 与迁移前原稿的可见 RGBA 哈希比较，验证尺寸和透明通道，并检查 SVG 嵌入实际还原后的表情。`test/widgets/stevessr_generator_page_test.dart` 检查两位角色的可用表情列表。

生成器报告压缩前后字节数：比较每组主图加全部完整 WebP 表情源稿，与实际打包的主图、差分及清单（原始备份 PNG 不参与比较）。这不是整个 APK/IPA 的大小降幅。
