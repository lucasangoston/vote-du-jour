/// Synthèse des mesures : cadence réelle du cron, délai vote -> site,
/// délai site -> dump, heures d'apparition.
library;

import 'classement.dart';
import 'csv.dart';
import 'heure_paris.dart';
import 'releve.dart';

/// Lit `heures_vote.csv` (colonnes `numero,heure_vote_paris`, heure au format
/// `AAAA-MM-JJ HH:MM`, saisie à la main depuis le compte rendu de séance).
Map<int, DateTime> lireHeuresVote(String csv) => {
      for (final m in lireCsvAvecEntete(csv))
        if ((m['heure_vote_paris'] ?? '').isNotEmpty)
          int.parse(m['numero']!):
              depuisParis(DateTime.parse(m['heure_vote_paris']!.replaceFirst(' ', 'T'))),
    };

String _min(Duration d) {
  final m = d.inSeconds / 60;
  return m >= 120 ? '${(m / 60).toStringAsFixed(1)} h' : '${m.round()} min';
}

Duration _mediane(List<Duration> l) {
  final t = [...l]..sort();
  return t[t.length ~/ 2];
}

Duration _max(List<Duration> l) => l.reduce((a, b) => a > b ? a : b);

String resumer(
  List<LigneReleve> releve,
  List<Map<String, String>> passages,
  Map<int, DateTime> heuresVote,
) {
  final b = StringBuffer('# Délai de publication des scrutins\n\n');

  // Cadence réelle : écarts entre passages consécutifs de moins de 2 h
  // (au-delà, c'est une nuit ou un week-end, pas un retard du cron).
  final instants = passages
      .map((p) => DateTime.tryParse(p['horodatage_utc'] ?? ''))
      .whereType<DateTime>()
      .toList()
    ..sort();
  final ecarts = <Duration>[
    for (var i = 1; i < instants.length; i++)
      if (instants[i].difference(instants[i - 1]) < const Duration(hours: 2))
        instants[i].difference(instants[i - 1]),
  ];
  final erreurs = passages.where((p) => p['statut'] != 'ok').length;
  b.writeln('- Passages : ${passages.length} ($erreurs en erreur)'
      '${ecarts.isEmpty ? '' : ', écart médian ${_min(_mediane(ecarts))}, maximal ${_min(_max(ecarts))}'}.');
  b.writeln('- Scrutins relevés : ${releve.length}, dont '
      '${releve.where((l) => Categorie.values.any((c) => c.code == l.categorie && c.retenue)).length} retenus par le filtrage.');

  final versDump = [
    for (final l in releve)
      if (l.apparitionDump != null) l.apparitionDump!.difference(l.apparitionSite),
  ];
  if (versDump.isNotEmpty) {
    b.writeln('- Site -> dump (${versDump.length} scrutins) : médian ${_min(_mediane(versDump))}, '
        'maximal ${_min(_max(versDump))}.');
  }

  final avecVote = releve.where((l) => heuresVote.containsKey(l.numero)).toList();
  if (avecVote.isNotEmpty) {
    final hauts = [for (final l in avecVote) l.apparitionSite.difference(heuresVote[l.numero]!)];
    final bas = [
      for (final l in avecVote)
        (l.passagePrecedent ?? l.apparitionSite).difference(heuresVote[l.numero]!),
    ];
    b
      ..writeln('- Vote -> site (${avecVote.length} scrutins avec heure de vote) : '
          'médian ${_min(_mediane(hauts))}, maximal ${_min(_max(hauts))} '
          '(borne basse : médian ${_min(_mediane(bas))}, maximal ${_min(_max(bas))}).')
      ..writeln()
      ..writeln('| N° | Vote (Paris) | Vu entre (Paris) | Délai | Titre |')
      ..writeln('|---:|---|---|---|---|');
    for (final l in avecVote) {
      final v = heuresVote[l.numero]!;
      final entre = l.passagePrecedent == null
          ? formatParis(l.apparitionSite)
          : '${formatParis(l.passagePrecedent!)} et ${formatParis(l.apparitionSite).substring(11)}';
      b.writeln('| ${l.numero} | ${formatParis(v)} | $entre | '
          '${_min(l.apparitionSite.difference(v))} | ${l.titre.length > 80 ? '${l.titre.substring(0, 80)}…' : l.titre} |');
    }
  } else {
    b.writeln('- Vote -> site : aucune heure de vote saisie dans heures_vote.csv.');
  }

  // Heures d'apparition sur le site, pour proposer les plages du cron.
  final parHeure = <int, int>{};
  for (final l in releve) {
    parHeure.update(versParis(l.apparitionSite).hour, (v) => v + 1, ifAbsent: () => 1);
  }
  if (parHeure.isNotEmpty) {
    b
      ..writeln()
      ..writeln('| Heure (Paris) | Scrutins apparus |')
      ..writeln('|---|---:|');
    for (final h in parHeure.keys.toList()..sort()) {
      b.writeln('| ${h}h | ${parHeure[h]} |');
    }
  }
  return b.toString();
}
