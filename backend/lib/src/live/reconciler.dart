import 'package:vote_contract/vote_contract.dart';

import '../dossier_index.dart';
import '../index_builder.dart';
import '../scrutin.dart';

/// Index publié et scrutins provisoires encore en attente du jeu de données.
class Reconciliation {
  const Reconciliation({required this.index, required this.pending});

  final DecisionIndex index;

  /// Scrutins provisoires que le jeu de données ne contient pas encore : ils
  /// restent provisoires et sont gardés pour les prochains passages.
  final List<Scrutin> pending;
}

/// Réunit les scrutins du jeu de données ([confirmed]) et les scrutins
/// provisoires lus sur le site ([provisional]) en un seul index.
///
/// - Un scrutin provisoire que le jeu de données contient est confirmé : la
///   version du jeu de données le remplace (même identifiant), qu'elle soit
///   retenue ou non. Le jeu de données est complet jusqu'à son dernier
///   numéro ([confirmedUpTo], par défaut le plus grand numéro de
///   [confirmed]) : un scrutin provisoire de numéro inférieur ou égal est
///   donc confirmé.
/// - Un scrutin provisoire absent du jeu de données reste publié, avec le
///   statut [DecisionStatus.provisoire].
/// - Sans scrutin provisoire, l'index est exactement celui de
///   [buildDecisionIndex].
///
/// Les deux sources passent ensemble par [buildDecisionIndex] : mêmes règles
/// de sélection (article unique compris), même rattachement aux dossiers,
/// même ordre. [arcs] (#67) ne concerne que les scrutins du jeu de données :
/// une décision provisoire n'a pas de vote par groupe, donc pas d'arc.
Reconciliation reconcile({
  required Iterable<Scrutin> confirmed,
  int? confirmedUpTo,
  Iterable<Scrutin> provisional = const [],
  required DateTime generatedAt,
  DossierIndex? dossiers,
  Map<String, List<HemicycleSegment>> arcs = const {},
  int limit = maxIndexDecisions,
}) {
  final confirmedList = confirmed.toList();
  final upTo =
      confirmedUpTo ??
      confirmedList.fold<int>(0, (max, s) => s.numero > max ? s.numero : max);
  final confirmedUids = {for (final s in confirmedList) s.uid};
  final byUid = <String, Scrutin>{};
  for (final s in provisional) {
    if (s.numero > upTo && !confirmedUids.contains(s.uid)) byUid[s.uid] = s;
  }
  final pending = byUid.values.toList()
    ..sort((a, b) => a.numero.compareTo(b.numero));

  final index = buildDecisionIndex(
    [...confirmedList, ...pending],
    generatedAt: generatedAt,
    dossiers: dossiers,
    arcs: arcs,
    limit: limit,
  );
  if (pending.isEmpty) return Reconciliation(index: index, pending: pending);
  return Reconciliation(
    index: DecisionIndex(
      generatedAt: index.generatedAt,
      source: index.source,
      decisions: [
        for (final d in index.decisions)
          byUid.containsKey(d.id) ? _provisional(d) : d,
      ],
    ),
    pending: pending,
  );
}

/// La même décision, au statut provisoire. Passer par le JSON garde tous les
/// champs du contrat, y compris ceux qui lui seront ajoutés.
DecisionSummary _provisional(DecisionSummary d) => DecisionSummary.tryFromJson({
  ...d.toJson(),
  'status': DecisionStatus.provisoire.json,
})!;
