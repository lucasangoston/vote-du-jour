import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

DecisionDetail _fixture(int numero) => DecisionDetail.fromJson(
  jsonDecode(
    File('test/fixtures/content/detail_$numero.json').readAsStringSync(),
  ),
);

String _title(DecisionDetail d) =>
    d.decision.summary!.shortTitle ?? d.decision.summary!.title;

void main() {
  final d = _fixture(8610);
  final text = postText(d, title: _title(d));
  final alt = altText(d, title: _title(d));

  List<String> check(String t, {String? a}) =>
      proofread(d, text: t, alt: a ?? alt);

  test('les brouillons des gabarits passent tous la relecture', () {
    for (final n in [8610, 7979, 8693, 9759]) {
      final x = _fixture(n);
      final title = _title(x);
      expect(
        proofread(
          x,
          text: postText(x, title: title),
          alt: altText(x, title: title),
        ),
        isEmpty,
        reason: '$n',
      );
    }
  });

  group('typographie', () {
    test('espace ordinaire avant les deux-points', () {
      expect(
        check(text.replaceFirst('Pour :', 'Pour :')),
        contains(contains('insécable')),
      );
    });

    test('ligne qui commence par une ponctuation', () {
      expect(
        check(text.replaceFirst(' : RN', '\n: RN')),
        contains('une ligne commence par une ponctuation'),
      );
    });

    test('espace avant une virgule, double espace', () {
      expect(
        check(text.replaceFirst('RN, DR', 'RN , DR')),
        contains('espace avant « , » ou « . »'),
      );
      expect(
        check(text.replaceFirst('Rejeté — ', 'Rejeté —  ')),
        contains('double espace'),
      );
    });
  });

  test('longueur : 300 au plus', () {
    final long = text.replaceFirst(
      'leperchoir.app',
      '${'x' * 200}\nleperchoir.app',
    );
    expect(check(long), contains(startsWith('${postLength(long)} caractères')));
  });

  group('complétude', () {
    test('verdict, lien et texte alternatif présents', () {
      expect(
        check(text.replaceFirst('Rejeté — ', 'Adopté — ')),
        contains('le post ne commence pas par « Rejeté — »'),
      );
      expect(
        check(text.replaceFirst('\nleperchoir.app', '')),
        contains('le lien leperchoir.app manque en fin de post'),
      );
      expect(
        proofread(d, text: text, alt: ' '),
        contains('texte alternatif absent'),
      );
    });
  });

  group('chiffres', () {
    test('un chiffre faux dans le post ou le texte alternatif', () {
      expect(
        check(text.replaceFirst('151 pour', '152 pour')),
        contains('post : 152 pour au lieu de 151'),
      );
      expect(
        check(text, a: alt.replaceFirst('187 contre', '178 contre')),
        contains('texte alternatif : 178 contre au lieu de 187'),
      );
    });

    test('un chiffre manquant ou inattendu', () {
      expect(
        check(text.replaceFirst(' · 187 contre', '')),
        contains('post : « 187 contre » manque'),
      );
      expect(
        check(text.replaceFirst('187 contre', '187 contre · 4 abst.')),
        contains('chiffre « 4 abst. » inattendu dans le post'),
      );
    });

    test('motion de censure : pour et 289 requis', () {
      final c = _fixture(7979);
      final t = postText(c, title: _title(c));
      expect(
        proofread(
          c,
          text: t.replaceFirst('289 requis', '288 requis'),
          alt: altText(c, title: _title(c)),
        ),
        contains('post : 288 requis au lieu de 289'),
      );
    });
  });

  test('neutralité : mot évaluatif signalé, accords compris', () {
    expect(
      check(text.replaceFirst('Donner aux', 'Donner enfin aux')),
      contains('mot évaluatif « enfin » dans le post'),
    );
    expect(
      check(text, a: '$alt Une décision historique.'),
      contains('mot évaluatif « historique » dans le texte alternatif'),
    );
    expect(
      check(
        text.replaceFirst('Donner aux', 'Une mesure importante : donner aux'),
      ),
      contains('mot évaluatif « importante » dans le post'),
    );
  });

  test('groupes : seulement les sigles du scrutin', () {
    expect(
      check(text.replaceFirst('RN, DR, UDR', 'RN, DR, UDR, XYZ')),
      contains('groupe inconnu « XYZ »'),
    );
  });

  test('l\'issue affiche le résultat de la relecture', () {
    const base = Draft(
      decisionId: 'A',
      sourceUrl: 'https://scrutin',
      title: 'Titre',
      text: 'Rejeté — Titre.\nleperchoir.app',
      alt: 'Carte Le Perchoir.',
      imageUrl: 'https://image',
    );
    final day = DateTime.utc(2026, 11, 14);
    expect(renderDailyIssue(day, [base]), contains('✅ Relecture OK'));
    expect(
      renderDailyIssue(day, [
        Draft(
          decisionId: base.decisionId,
          sourceUrl: base.sourceUrl,
          title: base.title,
          text: base.text,
          alt: base.alt,
          imageUrl: base.imageUrl,
          problems: const ['double espace'],
        ),
      ]),
      contains('⚠️ Relecture : à corriger avant publication\n- double espace'),
    );
  });
}
