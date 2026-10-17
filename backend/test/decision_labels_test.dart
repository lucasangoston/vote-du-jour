import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

/// Titre court et étape de chaque type de décision, calculés sur les vrais
/// scrutins et dossiers des fixtures, via l'index publié.
void main() {
  late Map<int, DecisionSummary> published;
  late Map<int, DecisionSummary> withoutDossiers;

  setUpAll(() {
    final scrutins = readScrutinsArchive(fixtureArchive());
    Map<int, DecisionSummary> build(DossierIndex? dossiers) => {
      for (final d in buildDecisionIndex(
        scrutins,
        generatedAt: DateTime.utc(2026, 10, 17),
        dossiers: dossiers,
      ).decisions)
        ?d.numero: d,
    };
    published = build(DossierIndex.fromArchive(fixtureDossiersArchive()));
    withoutDossiers = build(null);
  });

  void expectLabels(
    int numero, {
    required String shortTitle,
    required String stage,
    String? dossier,
  }) {
    final d = published[numero]!;
    expect(d.shortTitle, shortTitle, reason: 'scrutin $numero');
    expect(d.stage, stage, reason: 'scrutin $numero');
    expect(
      d.dossierUrl,
      dossier == null
          ? isNull
          : 'https://www.assemblee-nationale.fr/dyn/17/dossiers/$dossier',
      reason: 'scrutin $numero',
    );
  }

  group('vote sur l\'ensemble', () {
    test('titre du dossier et 1re lecture (217)', () {
      expectLabels(
        217,
        shortTitle:
            'Restaurer un système de retraite plus juste en annulant les '
            "dernières réformes portant sur l'âge de départ et le nombre "
            "d'annuités",
        stage: "1re lecture à l'AN",
        dossier: 'DLR5L17N50453',
      );
    });

    test('sans la formule « Proposition de loi visant à » (1194)', () {
      expectLabels(
        1194,
        shortTitle: 'Sortir la France du piège du narcotrafic',
        stage: "1re lecture à l'AN",
        dossier: 'DLR5L17N50169',
      );
    });

    test('chaque lecture a son libellé', () {
      expect(published[504]!.stage, "2e lecture à l'AN");
      expect(published[4696]!.stage, "Nouvelle lecture à l'AN");
      expect(published[4758]!.stage, "Lecture définitive à l'AN");
      expect(published[2278]!.stage, 'Texte de compromis (CMP)');
      expect(published[2278]!.shortTitle, "Profession d'infirmier");
    });
  });

  test('résolution : étiquette à la place de l\'étape (1018)', () {
    expectLabels(
      1018,
      shortTitle: 'Les effets psychologiques de TikTok sur les mineurs',
      stage: 'Résolution (sans valeur de loi)',
      dossier: 'DLR5L17N51279',
    );
  });

  group('motion de censure', () {
    test('après 49.3 : le texte en cause (519)', () {
      expectLabels(
        519,
        shortTitle:
            'Motion de censure : Projet de loi de financement de la sécurité '
            'sociale pour 2025',
        stage: 'Motion de censure',
        dossier: 'DLR5L17N50588',
      );
    });

    test('49.2 : ses auteurs, sans lien de dossier (5731)', () {
      expectLabels(
        5731,
        shortTitle:
            'Motion de censure déposée par Mme Mathilde Panot et 57 '
            'députés',
        stage: 'Motion de censure',
      );
    });
  });

  group('déclaration du Gouvernement', () {
    test('article 50-1 (4802)', () {
      expectLabels(
        4802,
        shortTitle:
            'Déclaration du Gouvernement sur la lutte contre le narcotrafic '
            'et la criminalité organisée',
        stage: 'Déclaration du Gouvernement',
      );
    });

    test('déclaration de politique générale (3054)', () {
      expectLabels(
        3054,
        shortTitle:
            'Déclaration de politique générale du Gouvernement de M. '
            'François Bayrou',
        stage: 'Déclaration de politique générale',
      );
    });
  });

  test('motion de rejet préalable adoptée : le texte rejeté (2873)', () {
    expectLabels(
      2873,
      shortTitle:
          'Réforme de l’audiovisuel public et souveraineté audiovisuelle',
      stage: "Motion de rejet préalable, 1re lecture à l'AN",
      dossier: 'DLR5L16N47697',
    );
  });

  test('rejet de la première partie du budget (4241)', () {
    expectLabels(
      4241,
      shortTitle: 'Projet de loi de finances pour 2026',
      stage: "Première partie du budget, 1re lecture à l'AN",
      dossier: 'DLR5L17N52428',
    );
  });

  test('sans dossiers : libellés tirés de l\'intitulé', () {
    final d = withoutDossiers[1194]!;
    expect(
      d.shortTitle,
      'Proposition de loi visant à sortir la France du piège du narcotrafic',
    );
    expect(d.stage, "1re lecture à l'AN");
    expect(d.dossierUrl, isNull);
    expect(
      withoutDossiers[2873]!.stage,
      "Motion de rejet préalable, 1re lecture à l'AN",
    );
    expect(
      withoutDossiers[2873]!.shortTitle,
      startsWith('Proposition de loi relative à la réforme de l'),
    );
    expect(withoutDossiers[1018]!.stage, 'Résolution (sans valeur de loi)');
  });

  test(
    'toute décision a un titre court et une étape, jamais « loi votée »',
    () {
      for (final d in [...published.values, ...withoutDossiers.values]) {
        expect(d.shortTitle, isNotEmpty, reason: 'scrutin ${d.numero}');
        expect(d.stage, isNotEmpty, reason: 'scrutin ${d.numero}');
        for (final label in [d.shortTitle!, d.stage!]) {
          expect(
            label.toLowerCase(),
            isNot(anyOf(contains('loi votée'), contains('promulgu'))),
          );
        }
      }
    },
  );

  test(
    'les libellés d\'un type sans lecture ne dépendent pas d\'une lecture',
    () {
      final labels = labelDecision(
        type: DecisionType.resolution,
        titre:
            "l'ensemble de la proposition de résolution X (première lecture).",
      );
      expect(labels.stage, resolutionLabel);
    },
  );
}
