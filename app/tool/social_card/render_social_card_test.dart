// Rend la carte réseau social d'une décision en PNG 1080 × 1350 (#109),
// pour la content factory (#106). Lancé sans écran par `flutter test`, qui
// fournit le moteur de rendu ; ce n'est pas un test.
//
// Depuis app/ :
//
//   SOCIAL_CARD_DETAIL=<détail v1/decisions/<id>.json> \
//   SOCIAL_CARD_OUT=<carte.png> \
//   [SOCIAL_CARD_TITLE=<titre écrit à la main>] \
//     flutter test tool/social_card/render_social_card_test.dart
//
// Écrit aussi <carte.png>.json :
//   {"status": "ok", "title": "...", "titleSize": 84}
//   {"status": "titre_a_ecrire"}   titre absent ou trop long : pas de PNG
//   {"status": "pas_de_carte"}     pas de scrutin public avec sièges
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/social_card/social_card.dart';
import 'package:votedujour/src/social_card/social_card_content.dart';
import 'package:votedujour/src/social_card/social_card_fonts.dart';

void main() {
  final env = Platform.environment;
  final detailPath = env['SOCIAL_CARD_DETAIL'];
  final out = env['SOCIAL_CARD_OUT'];
  final override = env['SOCIAL_CARD_TITLE'];

  testWidgets('carte réseau social', (tester) async {
    void report(Map<String, Object?> status) =>
        File('$out.json').writeAsStringSync(jsonEncode(status));

    final detail = DecisionDetail.fromJson(
      jsonDecode(File(detailPath!).readAsStringSync()),
    );
    final content = SocialCardContent.of(
      detail,
      title: override == null || override.trim().isEmpty
          ? null
          : override.trim(),
    );
    if (content == null) return report({'status': 'pas_de_carte'});

    await tester.runAsync(loadSocialCardFonts);
    final title = content.title;
    final titleSize = title == null ? null : socialTitleSize(title);
    if (title == null || titleSize == null) {
      return report({'status': 'titre_a_ecrire'});
    }

    tester.view
      ..physicalSize = socialCardSize
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: SocialCard(
            content: content,
            title: title,
            titleSize: titleSize,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File(out!).writeAsBytesSync(png!.buffer.asUint8List());
    });
    report({'status': 'ok', 'title': title, 'titleSize': titleSize});
  }, skip: detailPath == null || out == null);
}
