// Rend l'aperçu Bluesky d'un brouillon en PNG (#122) : le post tel qu'il
// apparaîtra dans un fil mobile. Lancé sans écran par `flutter test` ; ce
// n'est pas un test.
//
// Depuis app/ :
//
//   PREVIEW_CARD=<carte.png> PREVIEW_TEXT=<texte du post.txt> \
//   PREVIEW_OUT=<aperçu.png> \
//     flutter test tool/social_card/render_bluesky_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:votedujour/src/social_card/bluesky_preview.dart';
import 'package:votedujour/src/social_card/social_card_fonts.dart';

void main() {
  final env = Platform.environment;
  final cardPath = env['PREVIEW_CARD'];
  final textPath = env['PREVIEW_TEXT'];
  final out = env['PREVIEW_OUT'];

  testWidgets('aperçu Bluesky', (tester) async {
    await tester.runAsync(loadSocialCardFonts);
    final card = MemoryImage(File(cardPath!).readAsBytesSync());
    final text = File(textPath!).readAsStringSync().trimRight();

    tester.view
      ..physicalSize = const Size(blueskyPreviewWidth * 2, 3000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Align(
          alignment: Alignment.topCenter,
          child: RepaintBoundary(
            key: key,
            child: BlueskyPreview(text: text, card: card),
          ),
        ),
      ),
    );
    await tester.runAsync(() => precacheImage(card, key.currentContext!));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File(out!).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }, skip: cardPath == null || textPath == null || out == null);
}
