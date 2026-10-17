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
