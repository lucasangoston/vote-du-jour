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

/// Décisions provisoires sur l'ensemble du texte en débat : en attendant le
/// jeu de données, elles n'ont ni dossier rattaché ni résumé, et
/// s'afficheraient sous l'intitulé officiel complet. Une décision provisoire
/// non résumée qui vote l'ensemble du texte en débat ([DecisionIndex.inDebate],
/// même texte aux mots près, [sameVotedText]) en reprend le dossier et le
/// résumé (titre, titre court, explication, points).
///
/// Une fois le texte sorti du bloc « En débat », la décision garde ce
/// qu'elle avait dans l'index publié [published]. Ce résumé emprunté n'entre
/// pas dans le cache des résumés ([SummaryCache.adoptPublished] ignore les
/// décisions provisoires) : confirmée, la décision reçoit son propre résumé.
DecisionIndex withDebatedText(DecisionIndex index, {DecisionIndex? published}) {
  final before = {
    for (final d in published?.decisions ?? const <DecisionSummary>[])
      if (d.status == DecisionStatus.provisoire) d.id: d,
  };
  return index.withDecisions([
    for (final d in index.decisions)
      _withDebatedText(d, index.inDebate, before[d.id]),
  ]);
}

DecisionSummary _withDebatedText(
  DecisionSummary d,
  InDebate? debate,
  DecisionSummary? before,
) {
  if (d.status != DecisionStatus.provisoire ||
      d.type != DecisionType.ensembleTexte ||
      d.summary != null) {
    return d;
  }
  if (debate != null &&
      sameVotedText(d.officialTitle, [
        debate.shortTitle,
        ?debate.summary?.title,
      ])) {
    return _withDossier(d, debate.dossierUrl).withSummary(debate.summary);
  }
  if (before?.summary case final summary?) {
    return _withDossier(d, before!.dossierUrl).withSummary(summary);
  }
  return d;
}

/// [d] rattaché au dossier [url], s'il ne l'est pas déjà.
DecisionSummary _withDossier(DecisionSummary d, String? url) =>
    d.dossierUrl != null || url == null
    ? d
    : DecisionSummary.tryFromJson({...d.toJson(), 'dossierUrl': url})!;

/// La même décision, au statut provisoire. Passer par le JSON garde tous les
/// champs du contrat, y compris ceux qui lui seront ajoutés.
DecisionSummary _provisional(DecisionSummary d) => DecisionSummary.tryFromJson({
  ...d.toJson(),
  'status': DecisionStatus.provisoire.json,
})!;
