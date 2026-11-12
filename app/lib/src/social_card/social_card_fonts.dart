import 'package:flutter/services.dart';

import '../theme.dart';

/// Charge Geist et Newsreader depuis les assets de l'app. Sans écran
/// (`flutter test`), le moteur ne les charge pas seul : le texte sortirait
/// en rectangles et la mesure du titre ([socialTitleSize]) serait fausse.
Future<void> loadSocialCardFonts() async {
  Future<ByteData> font(String file) => rootBundle.load('assets/fonts/$file');
  await (FontLoader(geist)
        ..addFont(font('Geist-Regular.ttf'))
        ..addFont(font('Geist-Medium.ttf'))
        ..addFont(font('Geist-SemiBold.ttf'))
        ..addFont(font('Geist-Bold.ttf')))
      .load();
  await (FontLoader(newsreader)..addFont(font('Newsreader.ttf'))).load();
}
