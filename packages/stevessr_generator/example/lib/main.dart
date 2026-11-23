import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stevessr_generator/stevessr_generator.dart';

void main() => runApp(const GeneratorExampleApp());

const _imageInsertChannel =
    MethodChannel('com.github.lingyan000.fluxdo/generator_insert');

Future<void> insertGeneratedImage(StevessrExportedImage image) async {
  final accepted = await _imageInsertChannel.invokeMethod<bool>(
    'insertGeneratedImage',
    {
      'bytes': image.bytes,
      'mimeType': image.mimeType,
    },
  );
  if (accepted != true) throw StateError('Fluxdo did not accept the image');
}

class GeneratorExampleApp extends StatelessWidget {
  const GeneratorExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StevesSR Generator',
    theme: ThemeData(colorSchemeSeed: const Color(0xff6750a4), useMaterial3: true),
    home: const StevessrGeneratorPage(onInsert: insertGeneratedImage),
  );
}
