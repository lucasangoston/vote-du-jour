import 'package:vote_contract/vote_contract.dart';

import 'relative_date.dart';

/// Points de l'ordre du jour (bloc `upcoming` de l'index, #53) encore à
/// venir : ceux d'aujourd'hui (heure de Paris) ou plus tard, dans l'ordre
/// chronologique (ordre de l'index à heure égale). L'accueil y prend le
/// prochain vote solennel (#79) ; la liste n'a plus de section « À venir ».
List<UpcomingItem> upcomingToShow(
  List<UpcomingItem>? items, {
  required DateTime now,
}) {
  if (items == null || items.isEmpty) return const [];
  final today = parisDay(now);
  final indexed = [
    for (final (i, item) in items.indexed)
      if (!parisDay(item.startsAt).isBefore(today)) (i, item),
  ];
  indexed.sort((a, b) {
    final byTime = a.$2.startsAt.compareTo(b.$2.startsAt);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}
