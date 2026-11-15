import 'package:vote_contract/vote_contract.dart';

import 'daily_issue.dart';

/// Posts publiés sans correction d'affilée à partir desquels un format peut
/// passer en publication automatique (#113).
const autoPublishAfter = 30;

/// Seul format de la v1 : une carte et un texte sur Bluesky.
const blueskyCardFormat = 'carte Bluesky';

final _apostrophes = RegExp('[’‘\']');
// `\s` couvre aussi les espaces insécables (U+00A0, U+202F).
final _spaces = RegExp(r'\s+');

/// [s] sans les écarts de typographie qui ne comptent pas comme correction :
/// espaces (insécables comprises) et apostrophes.
String normalizeForComparison(String s) =>
    s.replaceAll(_apostrophes, "'").replaceAll(_spaces, ' ').trim();

/// Un post publié depuis une issue du jour, corrigé ou non par rapport au
/// brouillon généré.
typedef PublishedPost = ({DateTime day, int order, String id, bool corrected});

/// Posts publiés de l'issue du jour [body], dans l'ordre des blocs. Corrigé :
/// texte publié différent du texte d'origine après [normalizeForComparison],
/// ou titre écrit à la main.
List<PublishedPost> publishedPosts(String body) {
  final day = dailyIssueDay(body);
  if (day == null) return const [];
  final drafts = parseDailyIssue(body);
  return [
    for (final (i, d) in drafts.indexed)
      if (d.postUrl != null)
        (day: day, order: i, id: d.decisionId, corrected: _corrected(body, d)),
  ];
}

bool _corrected(String body, Draft draft) {
  final original = originalDraft(body, draft.decisionId);
  final generated = original?['text'];
  final published = draft.text;
  if (original?['title'] == null || generated == null || published == null) {
    return true;
  }
  return normalizeForComparison(published) != normalizeForComparison(generated);
}

/// Posts publiés sans correction d'affilée, les plus récents, d'après les
/// issues du jour [bodies] (ordre quelconque) : recalculé à chaque passage,
/// aucun état ailleurs. Une correction remet le compteur à zéro.
int uncorrectedStreak(Iterable<String> bodies) {
  final posts = [for (final b in bodies) ...publishedPosts(b)]
    ..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.order.compareTo(b.order);
    });
  var streak = 0;
  for (final p in posts.reversed) {
    if (p.corrected) break;
    streak++;
  }
  return streak;
}

/// Toujours validé à la main, quel que soit le compteur : vote solennel,
/// motion de censure, décision avec des arguments.
bool requiresManualReview(DecisionDetail detail) =>
    detail.decision.solennel ||
    detail.decision.type == DecisionType.motionDeCensure ||
    detail.arguments != null;

/// Le post de [detail] peut être publié sans validation : [streak] posts
/// sans correction d'affilée, et pas une exception.
bool canAutoPublish(DecisionDetail detail, {required int streak}) =>
    streak >= autoPublishAfter && !requiresManualReview(detail);
