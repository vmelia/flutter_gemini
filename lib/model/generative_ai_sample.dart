import 'package:flutter/material.dart';

import '../model.dart';
import '../widgets.dart';

final themeColor = ValueNotifier<Color>(Colors.orangeAccent);

class GenerativeAISample extends StatefulWidget {
  const GenerativeAISample({super.key, required this.title});
  final String title;

  @override
  State<GenerativeAISample> createState() => _GenerativeAISampleState();
}

class _GenerativeAISampleState extends State<GenerativeAISample> {
  String? apiKey;

  ThemeData theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(brightness: brightness, seedColor: themeColor.value);
    return ThemeData(brightness: brightness, colorScheme: colors, scaffoldBackgroundColor: colors.surface);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeColor,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: widget.title,
          theme: theme(Brightness.light),
          darkTheme: theme(Brightness.dark),
          themeMode: ThemeMode.system,
          home: switch (apiKey) {
            final providedKey? => Example(title: widget.title, apiKey: providedKey),
            _ => ApiKeyWidget(
              title: widget.title,
              onSubmitted: (key) {
                setState(() => apiKey = key);
              },
            ),
          },
        );
      },
    );
  }
}
