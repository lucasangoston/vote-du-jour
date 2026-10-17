import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

/// Titres réels du jeu de données des scrutins de la 17e législature (numéro
/// de scrutin en commentaire).
const adopte = VoteResult.adopte;
const rejete = VoteResult.rejete;

Classification classify(
  String titre, {
  String code = 'SPO',
  VoteResult sort = adopte,
}) => classifyScrutin(titre: titre, codeTypeVote: code, sort: sort);

Retained retained(DecisionType type, VoteResult result) =>
    Retained(type, result);

void main() {
  group('vote sur l\'ensemble d\'un texte', () {
    test('« l\'ensemble » avec apostrophe droite', () {
      // 217 (apostrophes typographiques plus loin dans le titre)
      expect(
        classify(
          "l'ensemble de la proposition de loi visant à restaurer un système de retraite plus juste en annulant les dernières réformes portant sur l’âge de départ et le nombre d’annuités (première lecture).",
          sort: rejete,
        ),
        retained(DecisionType.ensembleTexte, rejete),
      );
    });

    test('« l’ensemble » avec apostrophe typographique', () {
      // 2278
      expect(
        classify(
          'l’ensemble de la proposition de loi sur la profession d’infirmier (texte de la commission mixte paritaire).',
        ),
        retained(DecisionType.ensembleTexte, adopte),
      );
      // 7494
      expect(
        classify(
          'l’ensemble de la proposition de loi visant à réduire l’impact environnemental de l’industrie textile (texte de la commission mixte paritaire).',
          code: 'SPS',
        ),
        retained(DecisionType.ensembleTexte, adopte),
      );
    });

    test('ignore la casse et les espaces, y compris insécables', () {
      expect(
        classify(
          '  L’Ensemble  du projet de loi relatif à la protection des enfants (première lecture).',
        ),
        retained(DecisionType.ensembleTexte, adopte),
      );
    });
  });

  group('motion de censure', () {
    test('identifiée par le code MOC', () {
      // 519 (adoptée)
      expect(
        classify(
          "la motion de censure déposée en application de l'article 49, alinéa 3, de la Constitution par Mme Mathilde Panot, M. Boris Vallaud, Mme Cyrielle Chatelain, M. André Chassaigne et 181 membres de l'Assemblée.",
          code: 'MOC',
        ),
        retained(DecisionType.motionDeCensure, adopte),
      );
      // 5731 (rejetée)
      expect(
        classify(
          "la motion de censure, déposée en application de l'article 49, alinéa 2, de la Constitution, par Mme Mathilde Panot et 57 députés.",
          code: 'MOC',
          sort: rejete,
        ),
        retained(DecisionType.motionDeCensure, rejete),
      );
    });

    test('reconnue sur le titre quand le code est inconnu (site AN)', () {
      // 7979
      expect(
        classifyScrutin(
          titre:
              "la motion de censure déposée en application de l'article 49, alinéa 2, de la Constitution par Mmes Cyrielle Chatelain, Nadège Abomangoli et 56 députés.",
          codeTypeVote: null,
          sort: rejete,
        ),
        retained(DecisionType.motionDeCensure, rejete),
      );
    });
  });

  group('motion de rejet préalable', () {
    test('adoptée : retenue comme rejet du texte', () {
      // 2873
      expect(
        classify(
          "la motion de rejet préalable, déposée par Mme Cyrielle Chatelain, de la proposition de loi relative à la réforme de l'audiovisuel public et à la souveraineté audiovisuelle (première lecture).",
        ),
        retained(DecisionType.rejetPrealable, rejete),
      );
      // 2105 (apostrophes typographiques)
      expect(
        classify(
          'la motion de rejet préalable, déposée par MM. Julien Dive, Laurent Wauquiez, Gabriel Attal, Marc Fesneau et Paul Christophe de la proposition de loi visant à lever les contraintes à l’exercice du métier d’agriculteur (première lecture).',
        ),
        retained(DecisionType.rejetPrealable, rejete),
      );
    });

    test('rejetée : écartée, l\'examen du texte continue', () {
      // 6181
      expect(
        classify(
          'la motion de rejet préalable, déposée par M. Boris Vallaud, de la proposition de loi visant à renforcer la sécurité, la rétention administrative et la prévention des risques d’attentat (première lecture).',
          sort: rejete,
        ),
        const Excluded(ExclusionReason.rejetPrealableRejete),
      );
      // 7432 (coquille « péalable »)
      expect(
        classify(
          "la motion de rejet péalable, déposée par M. Patrick Hetzel, de la proposition de loi relative au droit à l'aide à mourir (nouvelle lecture).",
          sort: rejete,
        ),
        const Excluded(ExclusionReason.rejetPrealableRejete),
      );
    });
  });

  group('déclaration du Gouvernement', () {
    test('article 50-1', () {
      // 4802
      expect(
        classify(
          "la déclaration du Gouvernement portant sur la lutte contre le narcotrafic et la criminalité organisée (application de l'article 50-1 de la Constitution).",
          code: 'SPS',
        ),
        retained(DecisionType.declarationGouvernement, adopte),
      );
    });
  });

  group('amendement, sous-amendement, article : écartés', () {
    test('apostrophe droite', () {
      // 1014
      expect(
        classify(
          "l'amendement n° 18 de Mme Parmentier à l'article unique de la proposition de résolution tendant à la création d'une commission d'enquête sur les effets psychologiques de TikTok sur les mineurs.",
          sort: rejete,
        ),
        const Excluded(ExclusionReason.amendement),
      );
      // 2372
      expect(
        classify(
          "le sous-amendement n° 2780 du Gouvernement à l'amendement n° 593 de Mme Blin après l'article 19 du projet de loi de simplification de la vie économique (première lecture).",
          sort: rejete,
        ),
        const Excluded(ExclusionReason.sousAmendement),
      );
      // 2350
      expect(
        classify(
          "l'article 17 bis du projet de loi de simplification de la vie économique (première lecture).",
        ),
        const Excluded(ExclusionReason.article),
      );
    });

    test('apostrophe typographique', () {
      // 3022
      expect(
        classify(
          "l’amendement de suppression n° 499 de Mme Élisa Martin à l'article 18 de la proposition de loi portant création d'un statut de l'élu local (première lecture).",
          sort: rejete,
        ),
        const Excluded(ExclusionReason.amendement),
      );
      // 7349
      expect(
        classify(
          'l’article unique de la proposition de résolution visant à évaluer précisément le coût réel et sociétal de l’insécurité routière et son impact sur les finances publiques (article 34-1 de la Constitution).',
        ),
        const Excluded(ExclusionReason.article),
      );
    });

    test('un article voté en scrutin solennel reste écarté', () {
      // 988
      expect(
        classify(
          "l'article unique de la proposition de résolution européenne appelant au renforcement du soutien à l'Ukraine.",
          code: 'SPS',
        ),
        const Excluded(ExclusionReason.article),
      );
    });
  });

  group('partie d\'une loi de finances', () {
    test('« l\'ensemble de la … partie » n\'est pas un vote sur le texte', () {
      // 242 (deuxième partie adoptée)
      expect(
        classify(
          "l'ensemble de la deuxième partie du projet de loi de financement de la sécurité sociale pour 2025 (première lecture).",
        ),
        const Excluded(ExclusionReason.partieBudget),
      );
    });

    test('rejet de « l\'ensemble de la première partie » : le texte tombe', () {
      // 445
      expect(
        classify(
          "l'ensemble de la première partie du projet de loi de finances de fin des gestion pour 2024 (première lecture).",
          sort: rejete,
        ),
        retained(DecisionType.premierePartieBudget, rejete),
      );
    });
  });

  group('proposition de résolution (règle isolée : retainResolutions)', () {
    test('même traitement avec ou sans « l\'ensemble »', () {
      expect(retainResolutions, isTrue);
      // 1018
      expect(
        classify(
          "l'ensemble de la proposition de résolution tendant à la création d'une commission d'enquête sur les effets psychologiques de TikTok sur les mineurs.",
        ),
        retained(DecisionType.resolution, adopte),
      );
      // 2257
      expect(
        classify(
          'la proposition de résolution visant à abroger la loi n° 2023-270 du 14 avril 2023 de financement rectificative de la sécurité sociale pour 2023 dite réforme des retraites.',
        ),
        retained(DecisionType.resolution, adopte),
      );
    });
  });

  group('garde-fou des scrutins solennels', () {
    // Titre hypothétique : aucune tournure inconnue n'existe aujourd'hui en
    // scrutin solennel, le garde-fou anticipe une nouvelle formulation.
    const unknown =
        'le texte élaboré par la commission mixte paritaire sur le projet de loi exemple.';

    test('un intitulé inconnu en scrutin solennel est retenu', () {
      expect(
        classify(unknown, code: 'SPS'),
        retained(DecisionType.autre, adopte),
      );
    });

    test('le même intitulé en scrutin ordinaire est écarté et signalé', () {
      expect(classify(unknown), const Excluded(ExclusionReason.nonReconnu));
    });
  });

  group('les 47 titres non classés par la règle initiale (spike #15)', () {
    // test/fixtures/titres_non_classes.csv, produit par tools/spike_delai.
    final expected = <int, Classification>{
      // Première partie d'une loi de finances rejetée : le texte tombe.
      438: retained(DecisionType.premierePartieBudget, rejete),
      4241: retained(DecisionType.premierePartieBudget, rejete),
      // Autres votes sur une partie : étapes intermédiaires.
      3891: const Excluded(ExclusionReason.partieBudget),
      3597: const Excluded(ExclusionReason.partieBudget),
      4453: const Excluded(ExclusionReason.partieBudget),
      4595: const Excluded(ExclusionReason.partieBudget),
      4695: const Excluded(ExclusionReason.partieBudget),
      // Texte entier sans « l'ensemble ».
      6284: retained(DecisionType.ensembleTexte, adopte),
      8705: retained(DecisionType.ensembleTexte, adopte),
      8706: retained(DecisionType.ensembleTexte, adopte),
      // Déclaration de politique générale (le Gouvernement tombe).
      3054: retained(DecisionType.declarationGouvernement, rejete),
      // Propositions de résolution.
      for (final n in [1196, 1204, 2257, 2273, 2274, 3260, 4244, 5107, 5297])
        n: retained(DecisionType.resolution, adopte),
      for (final n in [8609, 8610, 8611, 8612])
        n: retained(DecisionType.resolution, rejete),
      // Procédure.
      for (final n in [
        737, 1301, 3272, // seconde délibération
        5128, 5782, 5784, 6132, 6255, 6269, // suspension de séance
        7575, 7576, 7577, 7578, 7579, 7580,
        1302, 7982, 8423, // prolongation de séance
      ])
        n: const Excluded(ExclusionReason.procedure),
      // Coquilles dans le titre officiel.
      1633: const Excluded(ExclusionReason.sousAmendement),
      6214: const Excluded(ExclusionReason.sousAmendement),
      4988: const Excluded(ExclusionReason.amendement),
      7950: const Excluded(ExclusionReason.article),
      // « sur la motion de rejet préalable », rejetée.
      5156: const Excluded(ExclusionReason.rejetPrealableRejete),
    };

    final rows = readCsv(
      File('test/fixtures/titres_non_classes.csv').readAsStringSync(),
    );

    test('le fichier contient les 47 cas attendus', () {
      expect(
        rows.map((r) => int.parse(r['numero']!)),
        unorderedEquals(expected.keys),
      );
    });

    for (final row in rows) {
      final numero = int.parse(row['numero']!);
      test('$numero : ${row['titre']!.substring(0, 50)}…', () {
        expect(
          classifyScrutin(
            titre: row['titre']!,
            codeTypeVote: row['type_vote'],
            sort: row['sort'] == 'adopté' ? adopte : rejete,
          ),
          expected[numero],
        );
      });
    }
  });
}

/// Lecteur CSV minimal (champs entre guillemets, `""` pour un guillemet).
List<Map<String, String>> readCsv(String text) {
  final records = <List<String>>[];
  var field = StringBuffer();
  var record = <String>[];
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      record.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n') {
      record.add(field.toString());
      records.add(record);
      field = StringBuffer();
      record = <String>[];
    } else if (c != '\r') {
      field.write(c);
    }
  }
  if (field.isNotEmpty || record.isNotEmpty) {
    record.add(field.toString());
    records.add(record);
  }
  final header = records.first;
  return [
    for (final r in records.skip(1))
      {for (var i = 0; i < header.length; i++) header[i]: r[i]},
  ];
}
