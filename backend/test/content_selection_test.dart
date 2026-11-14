import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

final _now = DateTime.utc(2026, 10, 20, 13);

const _summary = PlainSummary(
  title: 'Titre lisible',
  explanation: 'Une phrase.',
  promptVersion: 2,
);

const _group = GroupVoteDetail(
  organeRef: 'PO1',
  name: 'Groupe',
  position: GroupPosition.pour,
  count: VoteCount(pour: 10, contre: 0, abstentions: 0, nonVotants: 0),
);

/// Détail d'une décision de test : par défaut, vote sur l'ensemble d'un texte
/// en première lecture, confirmé, résumé, 300 pour et 200 contre, la veille.
DecisionDetail detail(
  String id, {
  int numero = 100,
  DecisionType type = DecisionType.ensembleTexte,
  DecisionStatus status = DecisionStatus.confirmee,
  VoteMode voteMode = VoteMode.scrutinPublic,
  DateTime? date,
  String? stage = "1re lecture à l'AN",
  String? dossierUrl,
  bool solennel = false,
  bool summarized = true,
  VoteTally count = const VoteTally(pour: 300, contre: 200, abstentions: 0),
  List<GroupVoteDetail> groups = const [_group],
  bool seats = true,
  DecisionArguments? arguments,
}) => DecisionDetail(
  decision: DecisionSummary(
    id: id,
    numero: voteMode == VoteMode.scrutinPublic ? numero : null,
    voteMode: voteMode,
    type: type,
    status: status,
    result: VoteResult.adopte,
    date: date ?? DateTime.utc(2026, 10, 19),
    officialTitle: "l'ensemble du texte $id",
    sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero',
    stage: stage,
    dossierUrl: dossierUrl ?? 'https://dossier/$id',
    summary: summarized ? _summary : null,
    count: voteMode == VoteMode.scrutinPublic ? count : null,
    solennel: solennel,
  ),
  groups: groups,
  seats: seats
      ? const [HemicycleSeat(place: 1, group: 'PO1', vote: SeatVote.pour)]
      : null,
  arguments: arguments,
);

List<String> select(
  List<DecisionDetail> details, {
  Set<String> handled = const {},
}) => [
  for (final d in selectPostDecisions(
    index: DecisionIndex(
      generatedAt: _now,
      decisions: [for (final d in details) d.decision],
    ),
    details: {for (final d in details) d.decision.id: d},
    handled: handled,
    now: _now,
  ))
    d.decision.id,
];

void main() {
  group('éligibilité', () {
    test('aucune décision éligible : liste vide', () {
      expect(select([]), isEmpty);
      expect(select([detail('A', status: DecisionStatus.provisoire)]), isEmpty);
    });

    test('exclues : provisoire, sans résumé, main levée, sans groupes, '
        'sans sièges, trop ancienne, déjà traitée', () {
      expect(
        select(
          [
            detail('provisoire', status: DecisionStatus.provisoire),
            detail('sans-resume', summarized: false),
            detail('main-levee', voteMode: VoteMode.mainLevee),
            detail('sans-groupes', groups: const []),
            detail('sans-sieges', seats: false),
            detail('ancienne', date: DateTime.utc(2026, 10, 12)),
            detail('traitee'),
            detail('ok'),
          ],
          handled: {'traitee'},
        ),
        ['ok'],
      );
    });

    test('7 jours tout juste : encore éligible', () {
      expect(select([detail('A', date: DateTime.utc(2026, 10, 13, 13))]), [
        'A',
      ]);
    });

    test('une décision sans fichier de détail n\'est pas éligible', () {
      final a = detail('A');
      expect(
        selectPostDecisions(
          index: DecisionIndex(generatedAt: _now, decisions: [a.decision]),
          details: const {},
          handled: const {},
          now: _now,
        ),
        isEmpty,
      );
    });
  });

  group('classement', () {
    test('vote important, puis texte entier, puis résolution', () {
      expect(
        select([
          detail(
            'resolution',
            type: DecisionType.resolution,
            stage: 'Résolution (sans valeur de loi)',
          ),
          detail('ensemble'),
          detail('solennel', solennel: true),
        ]),
        ['solennel', 'ensemble', 'resolution'],
      );
    });

    test('rejet de la première partie du budget : sort d\'un texte entier', () {
      expect(
        postPriority(
          detail('B', type: DecisionType.premierePartieBudget).decision,
        ),
        1,
      );
      expect(
        postPriority(detail('M', type: DecisionType.motionDeCensure).decision),
        0,
      );
    });

    test('à égalité : écart serré d\'abord', () {
      expect(
        select([
          detail('large', numero: 2),
          detail(
            'serre',
            numero: 1,
            count: const VoteTally(pour: 250, contre: 245, abstentions: 10),
          ),
        ]),
        ['serre', 'large'],
      );
    });

    test('puis configuration inhabituelle : unanimité ou groupe partagé', () {
      expect(
        select([
          detail('ordinaire', numero: 3),
          detail(
            'unanime',
            numero: 1,
            count: const VoteTally(pour: 87, contre: 0, abstentions: 15),
          ),
          detail(
            'partage',
            numero: 2,
            groups: const [
              GroupVoteDetail(
                organeRef: 'PO1',
                name: 'Groupe',
                position: GroupPosition.partage,
                count: VoteCount(
                  pour: 5,
                  contre: 5,
                  abstentions: 0,
                  nonVotants: 0,
                ),
              ),
            ],
          ),
        ]),
        ['partage', 'unanime', 'ordinaire'],
      );
    });

    test('puis présence d\'arguments, puis la plus récente', () {
      expect(
        select([
          detail('ancien', numero: 1, date: DateTime.utc(2026, 10, 15)),
          detail('recent', numero: 2),
          detail(
            'argumente',
            numero: 3,
            date: DateTime.utc(2026, 10, 14),
            arguments: DecisionArguments(
              source: ArgumentsSource(
                date: DateTime.utc(2026, 10, 14),
                url: 'https://compte-rendu',
              ),
              promptVersion: 1,
              pour: const [GroupArgument(group: 'Groupe', text: 'Argument.')],
            ),
          ),
        ]),
        ['argumente', 'recent', 'ancien'],
      );
    });

    test('écart serré : jamais pour une motion de censure', () {
      expect(
        isTightVote(
          detail(
            'M',
            type: DecisionType.motionDeCensure,
            count: const VoteTally(pour: 0, contre: 0, abstentions: 0),
          ).decision,
        ),
        isFalse,
      );
      expect(
        isTightVote(
          detail(
            'S',
            count: const VoteTally(pour: 100, contre: 97, abstentions: 0),
          ).decision,
        ),
        isTrue,
      );
    });
  });

  group('diversité', () {
    test('une décision par dossier, la mieux classée', () {
      expect(
        select([
          detail('budget-1', numero: 1, dossierUrl: 'https://plf'),
          detail(
            'budget-2',
            numero: 2,
            dossierUrl: 'https://plf',
            solennel: true,
          ),
          detail('autre', numero: 3),
        ]),
        ['budget-2', 'autre'],
      );
    });

    test('sans dossier : chaque décision est son propre dossier', () {
      final a = detail('A', numero: 1);
      final b = detail('B', numero: 2);
      DecisionDetail withoutDossier(DecisionDetail d) => DecisionDetail(
        decision: DecisionSummary(
          id: d.decision.id,
          numero: d.decision.numero,
          type: d.decision.type,
          status: d.decision.status,
          result: d.decision.result,
          date: d.decision.date,
          officialTitle: d.decision.officialTitle,
          sourceUrl: d.decision.sourceUrl,
          summary: d.decision.summary,
          count: d.decision.count,
        ),
        groups: d.groups,
        seats: d.seats,
      );
      expect(select([withoutDossier(a), withoutDossier(b)]), ['B', 'A']);
    });

    test('au plus 3 par jour', () {
      expect(select([for (var i = 1; i <= 5; i++) detail('D$i', numero: i)]), [
        'D5',
        'D4',
        'D3',
      ]);
    });
  });
}
