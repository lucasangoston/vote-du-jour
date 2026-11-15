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

/// La même décision avec un autre décompte (et un autre [result]).
DecisionDetail _withVote(
  DecisionDetail d,
  int pour,
  int contre,
  int abstentions, {
  String? result,
}) {
  final json = jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>;
  final decision = json['decision']! as Map<String, Object?>;
  decision['count'] = {
    'pour': pour,
    'contre': contre,
    'abstentions': abstentions,
  };
  if (result != null) decision['result'] = result;
  return DecisionDetail.fromJson(json);
}

void main() {
  group('texte du post', () {
    test('verdict et titre, chiffres, explication, lien', () {
      final d = _fixture(8610);
      expect(
        postText(d, title: _title(d)),
        'Rejeté — Donner aux acheteurs publics un critère de priorité '
        'nationale.\n'
        '151\u00A0pour · 187\u00A0contre.\n'
        '${d.decision.explanation}\n'
        'leperchoir.app',
      );
    });

    test('les groupes sont sur la carte, plus dans le texte', () {
      for (final n in [8610, 7979, 8693, 9759]) {
        final d = _fixture(n);
        final text = postText(d, title: _title(d));
        expect(text, isNot(contains('Pour :')), reason: '$n');
        expect(text, isNot(contains('groupes')), reason: '$n');
      }
    });

    test('verdict précisé : sans voix contre, sans voix pour, à N voix '
        'près, unanimité', () {
      expect(
        postText(_fixture(8693), title: 'Titre-restaurant'),
        startsWith('Adopté sans voix contre — Titre-restaurant.\n'),
      );
      expect(
        postText(_fixture(9759), title: 'Budget'),
        startsWith('Rejeté sans voix pour — Budget.\n'),
      );
      final d = _fixture(8610);
      DecisionDetail tally(int pour, int contre, {String? result}) =>
          _withVote(d, pour, contre, 0, result: result);
      expect(
        postText(tally(168, 170), title: 'T'),
        startsWith('Rejeté à 2 voix près — T.\n168 pour'),
      );
      expect(
        postText(tally(170, 170), title: 'T'),
        startsWith('Rejeté à égalité des voix — T.\n'),
      );
      expect(
        postText(tally(300, 0, result: 'adopte'), title: 'T'),
        startsWith('Adopté à l\'unanimité — T.\n'),
      );
    });

    test('fait saillant : voix manquantes, abstentions, participation', () {
      expect(
        postFact(_fixture(7979)),
        'Il manquait 157 voix sur les 289 requises.',
      );
      expect(postFact(_fixture(8693)), '102 députés sur 574 ont voté.');
      expect(postFact(_fixture(8610)), isNull);
      final d = _fixture(8610);
      expect(
        postFact(_withVote(d, 49, 63, 76)),
        'Plus d\'abstentions (76) que de votes pour ou contre.',
      );
    });

    test('mots-dièse : le compte, puis le type de décision', () {
      expect(
        postText(_fixture(7979), title: 'Motion de censure'),
        endsWith('\n#AssembléeNationale #MotionDeCensure\nleperchoir.app'),
      );
      expect(
        postText(_fixture(9759), title: 'Budget'),
        contains('\n#AssembléeNationale #Budget\n'),
      );
    });

    test('jamais plus de 300 caractères : les mots-dièse tombent, puis '
        'l\'explication, puis le fait saillant', () {
      // 8610 : l'explication publiée (171 caractères) ne laisse pas la place
      // des mots-dièse.
      final d = _fixture(8610);
      expect(postText(d, title: _title(d)), isNot(contains('#')));
      final court = postText(
        _withExplanation(d, 'Le texte vise les achats publics.'),
        title: _title(d),
      );
      expect(
        court,
        endsWith('Le texte vise les achats publics.\n$postTag\nleperchoir.app'),
      );
      final b = _fixture(8693);
      final long = postText(b, title: 'x' * 150);
      expect(long, contains('102 députés'));
      expect(long, isNot(contains(b.decision.explanation!)));
      final text = postText(b, title: 'x' * 225);
      expect(postLength(text), lessThanOrEqualTo(postMaxLength));
      expect(text, isNot(contains('députés')));
      expect(text, endsWith('\nleperchoir.app'));
    });

    test('motion de censure : pour et majorité requise, sans précision', () {
      final d = _fixture(7979);
      final text = postText(d, title: _title(d));
      expect(text, startsWith('Rejeté — '));
      expect(text, contains('132 pour · 289 requis.'));
    });

    test('pas de double point après une ponctuation forte', () {
      final d = _fixture(8610);
      expect(
        postText(d, title: 'Faut-il une priorité nationale ?'),
        startsWith('Rejeté — Faut-il une priorité nationale\u00A0?\n'),
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

  group('typographie et groupes (relecture du 14/11)', () {
    test(
      'espace insécable avant les deux-points : jamais en début de ligne',
      () {
        final d = _fixture(8610);
        expect(
          postText(d, title: 'Droits voisins de la presse : renforcer'),
          startsWith(
            'Rejeté — Droits voisins de la presse\u00A0: renforcer.\n',
          ),
        );
        expect(
          frenchTypography('« Oui » ; non ! Pourquoi ?'),
          '«\u00A0Oui\u00A0»\u00A0; non\u00A0! Pourquoi\u00A0?',
        );
      },
    );

    test('tous les groupes du même avis : « tous les groupes contre »', () {
      final d = _fixture(9759);
      expect(
        altText(d, title: 'Budget'),
        contains('Hémicycle coloré par le vote : tous les groupes contre.'),
      );
    });

    test('groupes partagés : « NI partagés », « SOC partagé »', () {
      expect(sharedGroups(['NI']), 'NI partagés');
      expect(sharedGroups(['SOC']), 'SOC partagé');
      expect(sharedGroups(['SOC', 'NI']), 'SOC, NI partagés');
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
          endsWith(
            'Adopté, 87 pour, 0 contre, 15 abstentions. 102 votants sur 574.',
          ),
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

  group('fil de réponses', () {
    test('arguments en séance : une réponse par camp, puis le scrutin', () {
      final d = _fixture(8610);
      final parts = threadParts(replyText(d));
      expect(parts, hasLength(2));
      expect(parts[0], startsWith('Les arguments en séance.\nPour (RN) : '));
      expect(parts[1], startsWith('Contre (LFI-NFP) : '));
      expect(
        parts[1],
        endsWith(
          '\nScrutin officiel : assemblee-nationale.fr/dyn/17/scrutins/8610',
        ),
      );
      for (final p in parts) {
        expect(postLength(p), lessThanOrEqualTo(postMaxLength));
      }
    });

    test('sans arguments : les points du résumé qui tiennent', () {
      final d = _fixture(8693);
      final parts = threadParts(replyText(d));
      expect(
        parts.single,
        startsWith('Ce que prévoit le texte :\n• Il met fin'),
      );
      expect(
        parts.single,
        contains('assemblee-nationale.fr/dyn/17/scrutins/8693'),
      );
      expect(postLength(parts.single), lessThanOrEqualTo(postMaxLength));
    });

    test('ni arguments ni points : le lien du scrutin seul', () {
      expect(
        replyText(_fixture(7979)),
        'Scrutin officiel : assemblee-nationale.fr/dyn/17/scrutins/7979',
      );
    });

    test('parties : séparées par une ligne « --- », vides ignorées', () {
      expect(threadParts(null), isEmpty);
      expect(threadParts(' \n'), isEmpty);
      expect(threadParts('A\n---\n\n---\nB\nC\n'), ['A', 'B\nC']);
    });
  });
}
