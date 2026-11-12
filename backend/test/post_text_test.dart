import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

/// Détails publiés de décisions réelles (#110) : résolution rejetée (8610),
/// motion de censure (7979), titre long à faible participation (8693),
/// budget rejeté (9759).
DecisionDetail _fixture(int numero) => DecisionDetail.fromJson(
  jsonDecode(
    File('test/fixtures/content/detail_$numero.json').readAsStringSync(),
  ),
);

String _title(DecisionDetail d) =>
    d.decision.summary!.shortTitle ?? d.decision.summary!.title;

/// La même décision avec l'explication [explanation].
DecisionDetail _withExplanation(DecisionDetail d, String explanation) {
  final s = d.decision.summary!;
  return DecisionDetail(
    decision: d.decision.withSummary(
      PlainSummary(
        title: s.title,
        shortTitle: s.shortTitle,
        explanation: explanation,
        promptVersion: s.promptVersion,
      ),
    ),
    count: d.count,
    groups: d.groups,
    seats: d.seats,
  );
}

void main() {
  group('texte du post', () {
    test('verdict et titre, chiffres, groupes, lien', () {
      final d = _fixture(8610);
      expect(
        postText(d, title: _title(d)),
        'Rejeté : Donner aux acheteurs publics un critère de priorité '
        'nationale.\n'
        '151 pour · 187 contre.\n'
        'Pour : RN, DR, UDR · Contre : EPR, LFI-NFP, SOC, EcoS, Dem, HOR, '
        'LIOT, GDR\n'
        'leperchoir.app',
      );
    });

    test('l\'explication seulement si tout tient', () {
      final d = _fixture(8610);
      final court = postText(
        _withExplanation(d, 'Le texte vise les achats publics.'),
        title: _title(d),
      );
      expect(court, contains('Le texte vise les achats publics.\n'));
      // L'explication publiée (171 caractères) ne tient pas : elle tombe.
      expect(
        postText(d, title: _title(d)),
        isNot(contains(d.decision.explanation!)),
      );
    });

    test('jamais plus de 300 caractères : la ligne des groupes tombe après '
        'l\'explication', () {
      final d = _fixture(9759);
      final long = 'x' * 200;
      final text = postText(d, title: long);
      expect(postLength(text), lessThanOrEqualTo(postMaxLength));
      expect(text, isNot(contains('Contre :')));
      expect(text, endsWith('\nleperchoir.app'));
    });

    test('motion de censure : pour et majorité requise, soutiens seuls', () {
      final d = _fixture(7979);
      final text = postText(d, title: _title(d));
      expect(text, contains('132 pour · 289 requis.'));
      expect(text, contains('Pour la censure : LFI-NFP, SOC, EcoS, LIOT, GDR'));
      expect(text, isNot(contains('Contre :')));
    });

    test('pas de double point après une ponctuation forte', () {
      final d = _fixture(8610);
      expect(
        postText(d, title: 'Faut-il une priorité nationale ?'),
        startsWith('Rejeté : Faut-il une priorité nationale ?\n'),
      );
    });

    test('les chiffres sont ceux des données, sur toutes les décisions', () {
      for (final n in [8610, 7979, 8693, 9759]) {
        final d = _fixture(n);
        final c = d.decision.count!;
        final text = postText(d, title: _title(d));
        expect(postLength(text), lessThanOrEqualTo(postMaxLength));
        expect(text, contains('${c.pour} pour'), reason: '$n');
      }
    });
  });

  group('texte alternatif', () {
    test('étape, date, titre, hémicycle par position, verdict et chiffres', () {
      final d = _fixture(8610);
      expect(
        altText(d, title: _title(d)),
        'Carte Le Perchoir. Résolution (sans valeur de loi), 8 octobre 2026. '
        'Donner aux acheteurs publics un critère de priorité nationale. '
        'Hémicycle coloré par le vote : pour, RN, DR, UDR ; contre, EPR, '
        'LFI-NFP, SOC, EcoS, Dem, HOR, LIOT, GDR. '
        'Rejeté, 151 pour, 187 contre.',
      );
    });

    test(
      'faible participation : « N votants », abstentions en toutes lettres',
      () {
        final d = _fixture(8693);
        expect(
          altText(d, title: _title(d)),
          endsWith('Adopté, 87 pour, 0 contre, 15 abstentions. 102 votants.'),
        );
      },
    );

    test('motion de censure : soutiens en blanc, majorité requise', () {
      final d = _fixture(7979);
      expect(
        altText(d, title: _title(d)),
        contains(
          'Hémicycle : en blanc, les députés qui ont voté la motion '
          '(LFI-NFP, SOC, EcoS, LIOT, GDR). Rejeté, 132 pour, 289 requis.',
        ),
      );
    });

    test('date : « 1er » le premier du mois', () {
      expect(frenchLongDate(DateTime.utc(2026, 10, 1)), '1er octobre 2026');
      expect(frenchLongDate(DateTime.utc(2026, 11, 4)), '4 novembre 2026');
    });
  });
}
