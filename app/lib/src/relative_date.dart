/// Dates relatives des décisions (« Aujourd'hui », « Hier », « Il y a 3
/// jours »), calculées au moment de l'affichage.
///
/// Mêmes règles que les widgets natifs (`RelativeDate.swift` et
/// `RelativeDate.kt`) :
///
/// - l'écart se compte en jours de calendrier, dans le fuseau du téléphone :
///   un vote du vendredi est « Il y a 3 jours » le lundi, week-end compris ;
/// - au-delà de six jours, la date complète (« 13 octobre 2026 ») ;
/// - une date future (horloge décalée) est affichée comme « Aujourd'hui ».
library;

/// Libellé de [day] (jour du vote, seuls l'année, le mois et le jour
/// comptent) vu depuis l'instant local [now].
String relativeDayLabel(DateTime day, {required DateTime now}) {
  // Deux minuits UTC : pas de décalage d'heure d'été dans la différence.
  final voteDay = DateTime.utc(day.year, day.month, day.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(voteDay).inDays;
  if (days <= 0) return "Aujourd'hui";
  if (days == 1) return 'Hier';
  if (days < 7) return 'Il y a $days jours';
  return formatFrenchDay(day);
}

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// « 13 octobre 2026 » (« 1er » pour le premier du mois).
String formatFrenchDay(DateTime day) {
  final dayOfMonth = day.day == 1 ? '1er' : '${day.day}';
  return '$dayOfMonth ${_months[day.month - 1]} ${day.year}';
}

const _weekdays = [
  'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche', //
];

/// Intertitre d'un groupe de décisions du même jour dans la liste :
/// « Aujourd'hui », « Hier », sinon « Mardi 13 octobre » (avec l'année si ce
/// n'est pas l'année en cours).
String dayGroupLabel(DateTime day, {required DateTime now}) {
  final voteDay = DateTime.utc(day.year, day.month, day.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(voteDay).inDays;
  if (days <= 0) return "Aujourd'hui";
  if (days == 1) return 'Hier';
  final year = day.year == now.year ? '' : ' ${day.year}';
  return '${formatFrenchWeekdayDay(day)}$year';
}

/// « Vendredi 23 octobre » (« 1er » pour le premier du mois), sans l'année :
/// titre de l'accueil (#79). Seuls l'année, le mois et le jour de [day]
/// comptent.
String formatFrenchWeekdayDay(DateTime day) {
  final date = DateTime.utc(day.year, day.month, day.day);
  final dayOfMonth = day.day == 1 ? '1er' : '${day.day}';
  return '${_weekdays[date.weekday - 1]} $dayOfMonth ${_months[day.month - 1]}';
}

const _shortMonths = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', //
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// « 13 oct. 2026 », ou « 13 oct. » sans [withYear] (« 1er » pour le
/// premier du mois).
String formatShortFrenchDate(DateTime date, {bool withYear = true}) {
  final day = date.day == 1 ? '1er' : '${date.day}';
  final month = _shortMonths[date.month - 1];
  return withYear ? '$day $month ${date.year}' : '$day $month';
}

/// Jour d'un point à venir de l'ordre du jour (#53), en heure de Paris, vu
/// depuis l'instant [now] : « Aujourd'hui », « Demain », sinon « Mardi 27
/// oct. » (« Mardi 27 octobre » avec [long], pour les lecteurs d'écran).
String upcomingDayLabel(
  DateTime instant, {
  required DateTime now,
  bool long = false,
}) {
  final day = parisDay(instant);
  final days = day.difference(parisDay(now)).inDays;
  if (days <= 0) return "Aujourd'hui";
  if (days == 1) return 'Demain';
  final date = long
      ? '${day.day == 1 ? '1er' : '${day.day}'} ${_months[day.month - 1]}'
      : formatShortFrenchDate(day, withYear: false);
  return '${_weekdays[day.weekday - 1]} $date';
}

/// Heure de Paris de [instant] : « 15h », « 21h30 ».
String parisHourLabel(DateTime instant) {
  final time = toParisTime(instant);
  return time.minute == 0
      ? '${time.hour}h'
      : '${time.hour}h${time.minute.toString().padLeft(2, '0')}';
}

/// Jour de [instant] en heure de Paris (minuit UTC de ce jour).
DateTime parisDay(DateTime instant) {
  final t = toParisTime(instant);
  return DateTime.utc(t.year, t.month, t.day);
}

/// Heure de Paris de [instant], sous forme de date « murale » UTC (seuls
/// ses champs comptent), quel que soit le fuseau du téléphone : l'ordre du
/// jour suit l'heure de Paris. Heure d'été européenne du dernier dimanche
/// de mars au dernier dimanche d'octobre, à 1 h UTC.
DateTime toParisTime(DateTime instant) {
  final utc = instant.toUtc();
  final summer =
      !utc.isBefore(_lastSundayAt1Utc(utc.year, 3)) &&
      utc.isBefore(_lastSundayAt1Utc(utc.year, 10));
  return utc.add(Duration(hours: summer ? 2 : 1));
}

DateTime _lastSundayAt1Utc(int year, int month) {
  // Dernier jour du mois, puis recul jusqu'au dimanche.
  final last = DateTime.utc(year, month + 1, 0, 1);
  return last.subtract(Duration(days: last.weekday % 7));
}

/// Ligne sous le quantième en grand de la carte d'un vote solennel de
/// l'accueil (#79), en heure de Paris : « Novembre · mardi 15 h »,
/// « Novembre · mardi 15 h 30 ».
String upcomingVoteLine(DateTime instant) {
  final time = toParisTime(instant);
  final month = _months[time.month - 1];
  final weekday = _weekdays[time.weekday - 1].toLowerCase();
  final minutes = time.minute == 0
      ? ''
      : ' ${time.minute.toString().padLeft(2, '0')}';
  return '${month[0].toUpperCase()}${month.substring(1)} · '
      '$weekday ${time.hour}\u00A0h$minutes';
}
