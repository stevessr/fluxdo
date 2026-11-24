import 'package:common_ui/common_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:stevessr_generator/stevessr_generator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ThemeData? hostTheme;
  try {
    hostTheme = PluginTheme.decode(
      await _imageInsertChannel.invokeMethod<String>('getHostTheme'),
    );
  } on MissingPluginException {
    // Older hosts and non-Android platforms use the system appearance.
  } on PlatformException {
    // A malformed or unavailable native channel must not block the editor.
  }
  runApp(GeneratorExampleApp(hostTheme: hostTheme));
}

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
  const GeneratorExampleApp({super.key, this.hostTheme});

  final ThemeData? hostTheme;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StevesSR Generator',
    theme: hostTheme ?? ThemeData(useMaterial3: true),
    darkTheme: hostTheme ?? ThemeData.dark(useMaterial3: true),
    themeMode: hostTheme == null
        ? ThemeMode.system
        : hostTheme!.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
    home: const StevessrGeneratorPage(onInsert: insertGeneratedImage),
  );
}
