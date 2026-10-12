import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/pages/stevessr_generator_page.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:path_provider/path_provider.dart';

const _returnChannel = MethodChannel(
  'com.github.lingyan000.fluxdo.plugin.sticker/return',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocale();
  runApp(
    TranslationProvider(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'FluxDO StevesSR',
        theme: ThemeData(useMaterial3: true, fontFamily: 'MiSans'),
        home: StevessrGeneratorPage(onInsert: _sendImageToHost),
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
