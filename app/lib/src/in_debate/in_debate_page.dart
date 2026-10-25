import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decision_detail/decision_detail_page.dart'
    show SummaryPoints, summaryPointsHeading;
import '../decision_list_page.dart' show capitalize, sourceNotice;
import '../decisions_repository.dart';
import '../hemicycle/external_link_row.dart';
import '../hemicycle/hemicycle_seats.dart';
import '../hemicycle/line_icon.dart';
import '../relative_date.dart';
import '../theme.dart';

/// Intertitre des articles votés.
const articlesHeading = 'Articles votés';

/// Mention d'un texte dont aucun article n'a encore été voté au scrutin
/// public.
const noArticleNotice = 'Aucun article voté au scrutin public pour l’instant.';

/// Écran « En débat » (#77), ouvert par la notification d'un texte qui passe
/// en séance : le texte du dossier [dossierRef], lu dans le bloc `inDebate`
/// de l'index.
///
/// L'index gardé hors ligne s'affiche tout de suite s'il porte ce texte ;
/// l'index en ligne le remplace à son arrivée. Si le texte n'est plus celui
/// en débat, l'écran le dit et renvoie au dossier.
class InDebatePage extends StatefulWidget {
  const InDebatePage({
    super.key,
    required this.dossierRef,
    required this.repository,
    this.now,
  });

  final String dossierRef;
  final DecisionsRepository repository;

  /// Instant de référence (tests) ; par défaut, l'heure courante.
  final DateTime? now;

  @override
  State<InDebatePage> createState() => _InDebatePageState();
}

class _InDebatePageState extends State<InDebatePage> {
  DecisionIndex? _index;

  /// L'index en ligne est arrivé : [_index] est le dernier publié.
  bool _fresh = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_index == null) {
      final cached = await widget.repository.readCached();
      if (mounted && cached != null && _index == null) {
        setState(() => _index = cached);
      }
    }
    try {
      final latest = await widget.repository.fetchLatest();
      if (mounted) {
        setState(() {
          _index = latest;
          _fresh = true;
        });
      }
    } catch (e) {
      debugPrint('InDebatePage : index indisponible : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    final inDebate = index?.inDebate?.dossierRef == widget.dossierRef
        ? index!.inDebate
        : null;
    final padding = MediaQuery.paddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            padding.top,
            20,
            40 + padding.bottom,
          ),
          children: [
            const HemicycleBackButton(),
            if (inDebate != null)
              ...inDebateContent(
                context,
                inDebate,
                upcoming: index!.upcoming,
                now: widget.now ?? DateTime.now(),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _fresh
                    ? _NoLongerInDebate(dossierRef: widget.dossierRef)
                    : _Unavailable(onRetry: _load),
              ),
          ],
        ),
      ),
    );
  }
}

/// Contenu de l'écran : carte d'attente (hémicycle gris, « En débat », vote
/// final), intitulé, titre, explication, points du résumé, articles votés,
/// lien du dossier et source.
List<Widget> inDebateContent(
  BuildContext context,
  InDebate inDebate, {
  List<UpcomingItem>? upcoming,
  required DateTime now,
}) {
  final colors = context.colors;
  final summary = inDebate.summary;
  final title = summary?.shortTitle ?? summary?.title ?? inDebate.shortTitle;
  return [
    const SizedBox(height: 8),
    _WaitingCard(finalVote: finalVoteLabel(inDebate, upcoming, now: now)),
    const SizedBox(height: 24),
    // Intitulé du texte au-dessus du titre court, s'il en diffère.
    if (title != inDebate.shortTitle) ...[
      Text(
        capitalize(inDebate.shortTitle),
        style: HemicycleText.meta.copyWith(color: colors.ink2),
      ),
      const SizedBox(height: 8),
    ],
    Semantics(
      header: true,
      child: Text(
        capitalize(title),
        style: HemicycleText.displayMd.copyWith(color: colors.ink),
      ),
    ),
    if (summary?.explanation case final explanation?) ...[
      const SizedBox(height: 12),
      Text(
        explanation,
        style: HemicycleText.bodySerif.copyWith(color: colors.body),
      ),
    ],
    if (summary?.points case final points? when points.isNotEmpty) ...[
      const SizedBox(height: 32),
      const _Heading(summaryPointsHeading),
      const SizedBox(height: 12),
      SummaryPoints(points),
    ],
    const SizedBox(height: 32),
    const _Heading(articlesHeading),
    const SizedBox(height: 12),
    if (inDebate.articles.isEmpty)
      Text(
        noArticleNotice,
        style: HemicycleText.bodySmall.copyWith(color: colors.ink2),
      )
    else
      ArticleTally(inDebate.articles),
    const SizedBox(height: 28),
    RuledRows(
      children: [
        ExternalLinkRow(label: 'Dossier législatif', url: inDebate.dossierUrl),
      ],
    ),
    const SizedBox(height: 24),
    Text(sourceNotice, style: HemicycleText.meta.copyWith(color: colors.ink2)),
  ];
}

/// « Vote final à venir », ou le jour du vote solennel du même dossier si
/// l'ordre du jour le donne ([upcoming]) : « Vote final aujourd'hui »,
/// « Vote final demain », « Vote final le mardi 27 octobre ».
String finalVoteLabel(
  InDebate inDebate,
  List<UpcomingItem>? upcoming, {
  required DateTime now,
}) {
  final votes = [
    for (final u in upcoming ?? const <UpcomingItem>[])
      if (u.kind == UpcomingKind.voteSolennel &&
          u.dossierRef == inDebate.dossierRef)
        u,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (votes.isEmpty) return 'Vote final à venir';
  final day = upcomingDayLabel(votes.first.startsAt, now: now, long: true);
  final lower = '${day[0].toLowerCase()}${day.substring(1)}';
  return switch (day) {
    "Aujourd'hui" || 'Demain' => 'Vote final $lower',
    _ => 'Vote final le $lower',
  };
}

/// Carte d'attente : l'hémicycle entier en gris, « En débat » en grand
/// dessous, puis le vote final.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.finalVote});

  final String finalVote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Surface douce à angle droit.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            WaitingHemicycle(width: math.min(340.0, constraints.maxWidth)),
            const SizedBox(height: 14),
            Text(
              'En débat',
              style: HemicycleText.displayLg.copyWith(color: colors.ink),
            ),
            const SizedBox(height: 14),
            Text(
              finalVote,
              textAlign: TextAlign.center,
              style: HemicycleText.bodySmall.copyWith(color: colors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Articles votés au scrutin public, comptés par sort : adoptés (pour),
/// supprimés et rejetés (contre). Le mot est toujours écrit sous le
/// chiffre.
class ArticleTally extends StatelessWidget {
  const ArticleTally(this.articles, {super.key});

  final List<DebatedArticle> articles;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    int count(ArticleOutcome o) => articles.where((a) => a.outcome == o).length;
    final figures = [
      (count(ArticleOutcome.adopte), 'adopté', colors.pour),
      (count(ArticleOutcome.supprime), 'supprimé', colors.contre),
      (count(ArticleOutcome.rejete), 'rejeté', colors.contre),
    ];
    String word(int n, String singular) => n > 1 ? '${singular}s' : singular;
    final label = [
      for (final (i, (n, singular, _)) in figures.indexed)
        i == 0
            ? '$n ${n > 1 ? 'articles' : 'article'} ${word(n, singular)}'
            : '$n ${word(n, singular)}',
    ].join(', ');
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        color: colors.surface,
        child: Row(
          children: [
            for (final (n, singular, color) in figures)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$n',
                      style: HemicycleText.figure.copyWith(color: color),
                    ),
                    Text(
                      word(n, singular),
                      style: HemicycleText.meta.copyWith(color: colors.ink2),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: HemicycleText.displaySm.copyWith(color: context.colors.ink),
    ),
  );
}

/// Le texte n'est plus celui en débat (index publié depuis) : lien vers son
/// dossier.
class _NoLongerInDebate extends StatelessWidget {
  const _NoLongerInDebate({required this.dossierRef});

  final String dossierRef;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Ce texte n’est plus en débat.',
        textAlign: TextAlign.center,
        style: HemicycleText.bodySmall.copyWith(color: context.colors.ink2),
      ),
      const SizedBox(height: 16),
      RuledRows(
        children: [
          ExternalLinkRow(
            label: 'Dossier législatif',
            url:
                'https://www.assemblee-nationale.fr/dyn/17/dossiers/'
                '${Uri.encodeComponent(dossierRef)}',
          ),
        ],
      ),
    ],
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Texte indisponible.',
        textAlign: TextAlign.center,
        style: HemicycleText.bodySmall.copyWith(color: context.colors.ink2),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
    ],
  );
}
