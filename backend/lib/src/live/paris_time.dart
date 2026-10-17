/// Heure de Paris sans base de fuseaux horaires : heure d'été du dernier
/// dimanche de mars, 01:00 UTC, au dernier dimanche d'octobre, 01:00 UTC
/// (règle européenne). Repris de l'outil du spike #15.
library;

DateTime _lastSunday(int year, int month) {
  var d = DateTime.utc(year, month + 1, 0, 1); // dernier jour du mois, 01:00
  while (d.weekday != DateTime.sunday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}

/// Décalage de Paris par rapport à UTC à l'instant [utc].
Duration parisOffset(DateTime utc) {
  final u = utc.toUtc();
  final summer =
      !u.isBefore(_lastSunday(u.year, 3)) &&
      u.isBefore(_lastSunday(u.year, 10));
  return Duration(hours: summer ? 2 : 1);
}

/// Heure de Paris à l'instant [utc], représentée par un `DateTime` UTC dont
/// les champs (jour, heure…) sont ceux de l'heure locale.
DateTime toParis(DateTime utc) => utc.toUtc().add(parisOffset(utc));

/// Jour de Paris à l'instant [utc], à minuit UTC (format des dates de
/// scrutin).
DateTime parisDay(DateTime utc) {
  final p = toParis(utc);
  return DateTime.utc(p.year, p.month, p.day);
}
