import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vote_contract/vote_contract.dart';

import 'hemicycle/line_icon.dart';
import 'hemicycle/result_style.dart';
import 'relative_date.dart';
import 'theme.dart';

/// Carte « En débat » sous la section « À venir » (#55) : le texte discuté
/// lors de la séance en cours ou de la dernière séance (bloc `inDebate` de
/// l'index) et ses derniers articles votés au scrutin public, sans chiffres.
/// Le tap ouvre le dossier législatif.
///
/// Rien n'est affiché sans texte en débat, sans article voté (le texte
/// figure déjà dans « À venir »), ni pour une séance de plus de 7 jours
/// (index relu hors ligne).
class InDebateSection extends StatelessWidget {
  const InDebateSection({super.key, required this.inDebate, this.now});

  final InDebate? inDebate;

  /// Instant de référence (tests) ; par défaut, l'heure courante.
  final DateTime? now;

  /// Nombre d'articles affichés avant « +N ».
  static const maxArticles = 6;

  @override
  Widget build(BuildContext context) {
    final d = inDebateToShow(inDebate, now: now ?? DateTime.now());
    if (d == null) return const SizedBox.shrink();
    final colors = context.colors;
    final shown = d.articles.take(maxArticles).toList();
    final more = d.articles.length - shown.length;
    final articles = [
      for (final a in shown) 'article ${a.number} ${_outcomeWord(a)}',
      if (more > 0) 'et $more autres articles votés',
    ].join(', ');
    final semanticsLabel =
        'En débat : ${d.shortTitle}. '
        '${articles[0].toUpperCase()}${articles.substring(1)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              header: true,
              child: Text(
                'En débat',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.ink2,
                ),
              ),
            ),
          ),
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              link: true,
              label: semanticsLabel,
              excludeSemantics: true,
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse(d.dossierUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.shortTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: HemicycleText.rowTitle.copyWith(
                                fontSize: 15,
                                color: colors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            MetaLine(
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.ink2,
                              ),
                              parts: [
                                for (final a in shown) _ArticleOutcome(a),
                                if (more > 0) Text('+$more'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      LineIcon(
                        LineGlyph.external,
                        size: 18,
                        strokeWidth: 1.8,
                        color: colors.ink2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Texte en débat à afficher à l'instant [now], ou `null` : sans article
/// voté, ou séance de plus de 7 jours (jours de Paris).
InDebate? inDebateToShow(InDebate? inDebate, {required DateTime now}) {
  if (inDebate == null || inDebate.articles.isEmpty) return null;
  final days = parisDay(now).difference(parisDay(inDebate.startsAt)).inDays;
  return days > 7 ? null : inDebate;
}

/// « Art. 38 adopté » : le sort en couleur (pour ou contre), le mot toujours
/// écrit.
class _ArticleOutcome extends StatelessWidget {
  const _ArticleOutcome(this.article);

  final DebatedArticle article;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: 'Art. ${article.number} '),
        TextSpan(
          text: _outcomeWord(article),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: switch (article.outcome) {
              ArticleOutcome.adopte => resultColor(context, VoteResult.adopte),
              ArticleOutcome.rejete || ArticleOutcome.supprime => resultColor(
                context,
                VoteResult.rejete,
              ),
            },
          ),
        ),
      ],
    ),
  );
}

String _outcomeWord(DebatedArticle a) => switch (a.outcome) {
  ArticleOutcome.adopte => 'adopté',
  ArticleOutcome.rejete => 'rejeté',
  ArticleOutcome.supprime => 'supprimé',
};
