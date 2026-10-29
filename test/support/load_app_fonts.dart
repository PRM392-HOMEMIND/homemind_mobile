import 'package:flutter/services.dart';

/// Use the application's bundled typography for layout and rendered-frame QA.
/// The default widget-test Ahem font cannot verify Vietnamese text wrapping.
Future<void> loadAppFonts() async {
  final fonts = FontLoader('BeVietnamPro');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
  }
  await fonts.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
