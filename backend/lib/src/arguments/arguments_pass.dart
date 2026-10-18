import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import '../decision_details.dart' show encodeDecisionDetail, detailCacheControl;
import '../dump_source.dart';
import '../object_store.dart';
import '../summary/llm_client.dart';
import 'arguments_matcher.dart';
import 'arguments_prompt.dart';
import 'arguments_state.dart';
import 'compte_rendu.dart';

/// Bornes d'un passage : elles plafonnent le coût du modèle.
class ArgumentsLimits {
  const ArgumentsLimits({this.maxCallsPerPass = 5, this.maxFailures = 3});

  /// Appels au modèle par passage.
  final int maxCallsPerPass;

  /// Échecs du modèle au-delà desquels une décision est abandonnée.
  final int maxFailures;
}

/// Ce dont le passage a besoin : le modèle, l'archive des comptes rendus et
/// ses bornes. Absent (pas de clé `ANTHROPIC_API_KEY`), il n'y a pas de
/// nouveaux arguments.
class ArgumentsService {
  const ArgumentsService({
    required this.llm,
    required this.comptesRendus,
    this.limits = const ArgumentsLimits(),
  });

  final LlmClient llm;
  final DumpSource comptesRendus;
  final ArgumentsLimits limits;
}

/// Bilan d'un passage.
class ArgumentsReport {
  ArgumentsReport();

  /// Décisions qui attendaient des arguments.
  int candidates = 0;

  /// L'archive des comptes rendus a été téléchargée.
  bool downloaded = false;

  /// Appels au modèle.
  int calls = 0;

  /// Décisions qui ont reçu des arguments.
  final published = <String>[];

  /// Décisions dont les explications de vote ne contenaient aucun argument.
  final empty = <String>[];

  /// Décisions à retenter, avec la raison.
  final pending = <String, String>{};

  final abandoned = <String>[];

  /// Décisions rattachées laissées pour un passage suivant (plafond).
  int deferred = 0;

  final warnings = <String>[];

  @override
  String toString() => [
    'Arguments : ${published.length} décisions argumentées, ${empty.length} '
        'sans argument, $calls appels au modèle, ${pending.length} à '
        'retenter, $deferred reportées (plafond du passage) ; $candidates '
        'décisions en attente, comptes rendus '
        '${downloaded ? 'téléchargés' : 'inchangés'}.',
    for (final MapEntry(:key, :value) in pending.entries)
      '  à retenter $key : $value',
    for (final id in abandoned) '  abandonnée $id',
    ...warnings.map((w) => 'Attention : $w'),
  ].join('\n');
}

/// Un passage, sur les fichiers de détail des décisions de l'index publié :
///
/// 1. les décisions qui peuvent recevoir des arguments ([isArgumentCandidate])
///    et ne les ont pas déjà (état [ArgumentsState] : faites pour la version
///    courante de la consigne, ou abandonnées) sont candidates ; sans
///    candidate, rien n'est téléchargé ;
/// 2. l'archive des comptes rendus (~59 Mo) n'est téléchargée que si elle a
///    changé (`If-Modified-Since`), ou si une décision déjà rattachée attend
///    son appel ;
/// 3. chaque candidate est rattachée à ses explications de vote
///    ([attachExplanations]) ; une décision sans explications rattachées
///    n'a rien et sera réexaminée avec la prochaine archive ;
/// 4. seules les explications de vote sont envoyées au modèle, au plus
///    [ArgumentsLimits.maxCallsPerPass] appels par passage, des plus
///    récentes aux plus anciennes ; après [ArgumentsLimits.maxFailures]
///    échecs, la décision est abandonnée.
///
/// Les arguments obtenus sont écrits dans l'état, puis dans les fichiers de
/// détail. La détection en direct n'appelle jamais ce passage.
Future<ArgumentsReport> runArgumentsPass({
  required ObjectStore store,
  required ArgumentsService service,
  DateTime Function() clock = DateTime.now,
}) async {
  final report = ArgumentsReport();
  final now = clock().toUtc();
  final index = await _readIndex(store, report.warnings);
  if (index == null) return report;
  final state = await ArgumentsState.read(store, report.warnings);

  bool done(String id) => switch (state[id]) {
    ArgumentsEntry(status: ArgumentsStatus.abandonne) => true,
    ArgumentsEntry(status: ArgumentsStatus.fait, :final promptVersion) =>
      promptVersion == argumentsPromptVersion,
    _ => false,
  };
  final todo = [
    for (final d in index.decisions)
      if (!done(d.id) &&
          d.status == DecisionStatus.confirmee &&
          d.voteMode == VoteMode.scrutinPublic &&
          argumentDecisionTypes.contains(d.type))
        d,
  ];
  report.candidates = todo.length;
  if (todo.isEmpty) return report;

  final waiting = todo.any(
    (d) => state[d.id]?.status == ArgumentsStatus.enAttente,
  );
  final DumpFetch fetch;
  try {
    fetch = await service.comptesRendus.fetch(
      ifModifiedSince: waiting ? null : state.lastModified,
    );
  } on Exception catch (e) {
    report.warnings.add('comptes rendus indisponibles ($e)');
    return report;
  }
  if (fetch is! DumpDownloaded) return report;
  report.downloaded = true;

  // Les détails des décisions du même jour servent aussi à vérifier qu'un
  // vote du compte rendu ne correspond qu'à une décision.
  final days = {for (final d in todo) d.date};
  final details = <DecisionDetail>[
    for (final d in index.decisions)
      if (days.contains(d.date)) ?await _readDetail(store, d.id),
  ];

  final attached = attachExplanations(
    details,
    readComptesRendusArchive(fetch.bytes, dates: days),
  );
  final todoIds = {for (final d in todo) d.id};
  final updated = <String, DecisionArguments>{};
  for (final detail in details) {
    final d = detail.decision;
    if (!todoIds.contains(d.id)) continue;
    final entry = state[d.id];
    final explanations = attached[d.id];
    if (explanations == null) {
      // Plus rattachée (compte rendu corrigé) : rien à attendre.
      if (entry?.status == ArgumentsStatus.enAttente) state.remove(d.id);
      continue;
    }
    final cr = explanations.compteRendu.uid;
    if (report.calls >= service.limits.maxCallsPerPass) {
      report.deferred++;
      state[d.id] = ArgumentsEntry(
        status: ArgumentsStatus.enAttente,
        updatedAt: now,
        compteRendu: cr,
        reason: entry?.reason ?? 'plafond du passage atteint',
        failures: entry?.failures ?? 0,
      );
      continue;
    }
    report.calls++;
    try {
      final response = await service.llm.createMessage(
        buildArgumentsRequest(decision: d, explanations: explanations),
      );
      final arguments = parseArgumentsResponse(
        response,
        explanations: explanations,
      );
      state[d.id] = ArgumentsEntry(
        status: ArgumentsStatus.fait,
        updatedAt: now,
        promptVersion: argumentsPromptVersion,
        compteRendu: cr,
        arguments: arguments,
        model: response['model'] is String
            ? response['model'] as String
            : summaryModel,
      );
      if (arguments == null) {
        report.empty.add(d.id);
      } else {
        updated[d.id] = arguments;
        report.published.add(d.id);
      }
    } on LlmException catch (e) {
      final failures = (entry?.failures ?? 0) + 1;
      final abandon = failures >= service.limits.maxFailures;
      state[d.id] = ArgumentsEntry(
        status: abandon ? ArgumentsStatus.abandonne : ArgumentsStatus.enAttente,
        updatedAt: now,
        compteRendu: cr,
        reason: '$e',
        failures: failures,
      );
      if (abandon) {
        report.abandoned.add(d.id);
      } else {
        report.pending[d.id] = 'échec du modèle ($e)';
      }
    }
  }
  state.lastModified = fetch.lastModified;
  await state.write(store);

  for (final detail in details) {
    final arguments = updated[detail.decision.id];
    if (arguments == null) continue;
    await store.write(
      decisionDetailPath(detail.decision.id),
      encodeDecisionDetail(detail.withArguments(arguments)),
      cacheControl: detailCacheControl,
    );
  }
  return report;
}

Future<DecisionIndex?> _readIndex(
  ObjectStore store,
  List<String> warnings,
) async {
  final raw = await store.read(indexPath);
  if (raw == null) return null;
  try {
    return DecisionIndex.fromJson(jsonDecode(raw));
  } on Object catch (e) {
    warnings.add('index publié illisible, arguments reportés ($e)');
    return null;
  }
}

Future<DecisionDetail?> _readDetail(ObjectStore store, String id) async {
  final raw = await store.read(decisionDetailPath(id));
  if (raw == null) return null;
  try {
    return DecisionDetail.fromJson(jsonDecode(raw));
  } on Object {
    return null;
  }
}
