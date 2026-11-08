import 'dart:io';

import 'package:vote_job/vote_job.dart';

/// Audit : sièges de tous les scrutins du jeu de données, avec l'annuaire
/// des organes. Usage : `dart run tool/seats_audit.dart AMO.zip Scrutins.zip`
void main(List<String> args) {
  final groups = GroupDirectory.fromArchive(File(args[0]).readAsBytesSync());
  final scrutins = readScrutinsArchive(File(args[1]).readAsBytesSync());
  final history = PlaceHistory.fromScrutins(scrutins);
  final byKind = <String, List<String>>{};
  var ok = 0;
  for (final s in scrutins) {
    try {
      hemicycleSeats(s, groups, history: history);
      ok++;
    } on SeatsMismatch catch (e) {
      final kind = e.message.contains('sans siège libre')
          ? 'sans siège libre'
          : e.message.replaceAll(RegExp(r'P[AO]\d+|\d+'), '#');
      byKind
          .putIfAbsent(kind, () => [])
          .add(
            '${s.numero} ${s.date.toIso8601String().substring(0, 10)} ${e.message}',
          );
    }
  }
  stdout.writeln('${scrutins.length} scrutins, $ok sièges cohérents');
  for (final MapEntry(:key, :value) in byKind.entries) {
    stdout.writeln('${value.length} × $key');
    for (final l in value.take(3)) {
      stdout.writeln('    $l');
    }
  }
  final dates = [
    for (final v in byKind.values)
      for (final l in v) l.split(' ')[1],
  ]..sort();
  if (dates.isNotEmpty) {
    stdout.writeln('dates : ${dates.first} → ${dates.last}');
  }
}
