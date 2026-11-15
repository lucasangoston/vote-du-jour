import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/social_card/bluesky_preview.dart';
import 'package:votedujour/src/social_card/social_card.dart';
import 'package:votedujour/src/social_card/social_card_content.dart';
import 'package:votedujour/src/social_card/social_card_fonts.dart';
import 'package:votedujour/src/theme.dart';

/// Détails publiés de cinq décisions réelles (#109) : titre court adopté
/// (9241), titre de 82 caractères à faible participation (8693), résolution
/// rejetée (8610), motion de censure (7979), budget rejeté (9759).
DecisionDetail _fixture(int numero) => DecisionDetail.fromJson(
  jsonDecode(
    File('test/fixtures/social_card/detail_$numero.json').readAsStringSync(),
  ),
);

SocialCardContent _content(int numero, {String? title}) =>
    SocialCardContent.of(_fixture(numero), title: title)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contenu', () {
    test('languette : étape raccourcie, date insécable, capitales', () {
      expect(
        _content(9759).tab,
        '1RE PARTIE DU BUDGET · 1RE LECTURE · 4 NOV. 2026',
      );
      expect(_content(9241).tab, '1RE LECTURE · 29 OCT. 2026');
    });

    test(
      'titre : titre court du résumé, sinon son titre, sinon le titre écrit',
      () {
        expect(_content(9241).title, 'Soins des victimes de violences');
        expect(
          _content(8693).title,
          'Titre-restaurant\u00A0: passage au format dématérialisé et '
          'transparence des commissions',
        );
        expect(
          _content(8693, title: 'Titre-restaurant').title,
          'Titre-restaurant',
        );
      },
    );

    test('chiffres sur une ligne, « 0 abst. » omis', () {
      expect(_content(8610).figures, '151 pour  ·  187 contre');
      expect(_content(9759).figures, '0 pour  ·  458 contre  ·  2 abst.');
    });

    test('motion de censure : pour et majorité requise, pas de votants', () {
      final c = _content(7979);
      expect(c.censure, isTrue);
      expect(c.figures, '132 pour  ·  289 requis');
      expect(c.turnout, isNull);
    });

    test('« N votants » seulement sous la moitié des sièges', () {
      expect(_content(8693).turnout, '102\u00A0votants sur\u00A0574');
      expect(_content(9241).turnout, startsWith('267\u00A0votants sur\u00A0'));
      expect(_content(8610).turnout, isNull);
      expect(
        socialTurnout(
          const VoteTally(pour: 1, contre: 0, abstentions: 0),
          574,
          censure: false,
        ),
        '1\u00A0votant sur\u00A0574',
      );
    });

    test(
      'légende : les groupes par camp, unanimité, soutiens de la censure',
      () {
        expect(_content(8610).legend, [
          (position: GroupPosition.pour, label: 'Pour', groups: 'RN, DR, UDR'),
          (
            position: GroupPosition.contre,
            label: 'Contre',
            groups: 'EPR, LFI-NFP, SOC, EcoS, Dem, HOR, LIOT, GDR',
          ),
        ]);
        expect(_content(9759).legend.single.label, 'Tous les groupes contre');
        expect(_content(9759).legend.single.groups, isEmpty);
        expect(_content(7979).legend, [
          (
            position: GroupPosition.pour,
            label: 'Pour la censure',
            groups: 'LFI-NFP, SOC, EcoS, LIOT, GDR',
          ),
        ]);
      },
    );

    test('pas de carte sans sièges ni décompte', () {
      final d = _fixture(8610);
      expect(
        SocialCardContent.of(
          DecisionDetail(
            decision: d.decision,
            count: d.count,
            groups: d.groups,
            source: d.source,
          ),
        ),
        isNull,
      );
    });

    test('couleur des sièges : le vote ; censure en encre neutre', () {
      expect(
        socialSeatColor(SeatVote.pour, censure: false),
        const Color(0xFF4FB08F),
      );
      expect(
        socialSeatColor(SeatVote.pour, censure: true),
        HemicycleColors.dark.ink,
      );
      expect(
        socialSeatColor(SeatVote.contre, censure: true),
        const Color(0xFFB5461F),
      );
    });
  });

  group('titre', () {
    setUpAll(loadSocialCardFonts);

    test('réduit pour tenir en 3 lignes, jamais tronqué', () {
      expect(socialTitleSize('Soins des victimes de violences'), 84);
      final long = _content(8693).title!;
      final size = socialTitleSize(long);
      expect(size, isNotNull);
      expect(size, lessThan(84));
    });

    test('trop long même à 48 px : titre à écrire', () {
      expect(socialTitleSize(List.filled(40, 'Interdire').join(' ')), isNull);
    });
  });

  group('rendu', () {
    setUpAll(loadSocialCardFonts);

    for (final numero in [9241, 8693, 8610, 7979, 9759]) {
      testWidgets('carte $numero', (tester) async {
        tester.view
          ..physicalSize = socialCardSize
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final content = _content(numero);
        final title = content.title!;
        await tester.pumpWidget(
          MaterialApp(
            home: SocialCard(
              content: content,
              title: title,
              titleSize: socialTitleSize(title)!,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(SocialCard),
          matchesGoldenFile('goldens/carte-sociale-$numero.png'),
        );
      });
    }
  });

  group('aperçu Bluesky (#122)', () {
    setUpAll(loadSocialCardFonts);

    testWidgets('fil : post avec carte, mots-dièse et lien, puis réponses', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(blueskyPreviewWidth, 1300)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final card = MemoryImage(
        File('test/goldens/carte-sociale-8610.png').readAsBytesSync(),
      );
      const text =
          'Rejeté — Donner aux acheteurs publics un critère de priorité '
          'nationale.\n151 pour · 187 contre.\n'
          '#AssembléeNationale\nleperchoir.app';
      const replies = [
        'Les arguments en séance.\nPour (RN) : le texte donne une '
            'liberté aux acheteurs publics.',
        'Contre (LFI-NFP) : le texte ne crée aucune obligation.\n'
            'Scrutin officiel : assemblee-nationale.fr/dyn/17/scrutins/8610',
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              child: BlueskyPreview(text: text, card: card, replies: replies),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(card, tester.element(find.byType(BlueskyPreview))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('@leperchoir.app'), findsNWidgets(3));
      expect(find.byType(Image), findsOneWidget);
      await expectLater(
        find.byType(BlueskyPreview),
        matchesGoldenFile('goldens/apercu-bluesky-8610.png'),
      );
    });
  });
}
