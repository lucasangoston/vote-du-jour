import 'dart:convert';

import 'package:vote_contract/vote_contract.dart';

import 'dump_reader.dart';
import 'dump_source.dart';
import 'index_builder.dart';
import 'object_store.dart';
import 'scrutin.dart';

/// Clé de l'état du job dans le bucket : le `Last-Modified` du dernier jeu de
/// données traité.
const stateKey = 'state/scrutins-dump.json';

/// Cache HTTP de l'index : court, le job tourne toutes les heures.
const indexCacheControl = 'public, max-age=300';

/// Issue d'une exécution du job.
sealed class JobOutcome {
  const JobOutcome();
}

/// Le jeu de données n'a pas changé : rien n'a été retraité ni republié.
class JobSkipped extends JobOutcome {
  const JobSkipped();

  @override
  String toString() => 'Jeu de données inchangé : rien à publier.';
}

/// Un nouvel index a été publié.
class JobPublished extends JobOutcome {
  const JobPublished({
    required this.scrutins,
    required this.index,
    required this.unrecognized,
  });

  /// Nombre de scrutins lus dans le jeu de données.
  final int scrutins;
  final DecisionIndex index;

  /// Scrutins écartés faute de règle reconnaissant leur intitulé, à relire.
  final List<Scrutin> unrecognized;

  @override
  String toString() => [
    '$scrutins scrutins lus, ${index.decisions.length} décisions publiées '
        'dans $indexPath.',
    if (unrecognized.isNotEmpty)
      '${unrecognized.length} intitulés non reconnus, écartés (à relire) :',
    for (final s in unrecognized)
      '  ${s.numero} (${s.codeTypeVote}) ${s.titre}',
  ].join('\n');
}

/// Exécute le job : récupère le jeu de données s'il a changé depuis la
/// dernière exécution, publie l'index des dernières décisions, puis enregistre
/// l'état. L'état n'est écrit qu'après la publication : en cas d'échec, la
/// prochaine exécution retraite le même jeu de données.
///
/// [force] ignore l'état et retraite le jeu de données.
Future<JobOutcome> runJob({
  required DumpSource source,
  required ObjectStore store,
  DateTime Function() clock = DateTime.now,
  bool force = false,
}) async {
  final previous = force ? null : _readLastModified(await store.read(stateKey));
  final fetch = await source.fetch(ifModifiedSince: previous);
  switch (fetch) {
    case DumpNotModified():
      return const JobSkipped();
    case DumpDownloaded(:final bytes, :final lastModified):
      final scrutins = readScrutinsArchive(bytes);
      final now = clock().toUtc();
      final index = buildDecisionIndex(scrutins, generatedAt: now);
      await store.write(
        indexPath,
        const JsonEncoder.withIndent('  ').convert(index.toJson()),
        cacheControl: indexCacheControl,
      );
      await store.write(
        stateKey,
        jsonEncode({
          'lastModified': lastModified,
          'processedAt': now.toIso8601String(),
        }),
        cacheControl: 'no-store',
      );
      return JobPublished(
        scrutins: scrutins.length,
        index: index,
        unrecognized: unrecognizedScrutins(scrutins),
      );
  }
}

String? _readLastModified(String? state) {
  if (state == null) return null;
  try {
    final json = jsonDecode(state);
    return json is Map && json['lastModified'] is String
        ? json['lastModified'] as String
        : null;
  } on FormatException {
    return null;
  }
}
