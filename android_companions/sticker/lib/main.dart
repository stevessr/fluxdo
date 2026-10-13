import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';
import 'pages/stevessr_generator_page.dart';
import 'services/local_notification_service.dart';
import 'services/stevessr_export_service.dart';
import 'package:path_provider/path_provider.dart';

const _returnChannel = MethodChannel(
  'com.github.lingyan000.fluxdo.plugin.sticker/return',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocale();
  final isInsertMode = await _returnChannel.invokeMethod<bool>('insertMode') ?? false;
  runApp(
    TranslationProvider(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'FluxDO StevesSR',
        theme: ThemeData(useMaterial3: true, fontFamily: 'MiSans'),
        home: StevessrGeneratorPage(
          onInsert: isInsertMode ? _sendImageToHost : null,
        ),
      ),
    ),
  );
}

/// Return an actual image, never a raw file:// path or a giant Binder blob.
/// The Android activity packages it as a grantable content:// URI.
Future<void> _sendImageToHost(StevessrExportedImage image) async {
  final extension = image.extension.toLowerCase();
  if (!{'png', 'webp', 'avif', 'jpg', 'svg'}.contains(extension)) {
    throw ArgumentError.value(extension, 'extension');
  }
  if (image.bytes.isEmpty || image.bytes.length > 16 * 1024 * 1024) {
    throw StateError('Export exceeds companion transfer size limit');
  }
  final temp = await getTemporaryDirectory();
  final file = File(
    '${temp.path}/stevessr-${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await file.writeAsBytes(image.bytes, flush: true);
  try {
    await _returnChannel.invokeMethod<void>('complete', {
      'path': file.path,
      'mimeType': image.mimeType,
      'extension': extension,
    });
  } on PlatformException {
    rethrow;
  }
}
