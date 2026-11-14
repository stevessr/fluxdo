import 'package:flutter/material.dart';
import 'package:stevessr_generator/stevessr_generator.dart';

void main() => runApp(const GeneratorExampleApp());

class GeneratorExampleApp extends StatelessWidget {
  const GeneratorExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StevesSR Generator',
    theme: ThemeData(colorSchemeSeed: const Color(0xff6750a4), useMaterial3: true),
    home: const StevessrGeneratorPage(),
  );
}
