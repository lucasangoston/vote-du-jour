import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decision_list_page.dart'
    show capitalize, formatFrenchDate, sourceNotice;
import '../hemicycle/external_link_row.dart';
import '../hemicycle/line_icon.dart';
import '../hemicycle/result_style.dart';
import '../hemicycle/vote_arc.dart';
import '../provisional_badge.dart';
import '../theme.dart';
import 'decision_detail_repository.dart';
import 'vote_arguments.dart';
import 'who_voted_what.dart';

/// Écran de détail d'une décision : carte du vote (grand arc, résultat,
/// décompte), méta, titre, explication, points du résumé, « Qui a voté
/// quoi » (groupes rangés par position), « Pourquoi ils ont voté ainsi »
/// (arguments des groupes), liens vers les pages officielles et source.
///
/// [summary] (la ligne de la liste) s'affiche tout de suite, arc compris ;
/// le fichier de détail complète l'écran quand il arrive. Ouvert depuis un
/// widget, seul [id] est connu.
class DecisionDetailPage extends StatefulWidget {
  const DecisionDetailPage({
    super.key,
    required this.id,
    required this.repository,
    this.summary,
  });

  final String id;
  final DecisionDetailRepository repository;
  final DecisionSummary? summary;

  @override
  State<DecisionDetailPage> createState() => _DecisionDetailPageState();
}

class _DecisionDetailPageState extends State<DecisionDetailPage> {
  DecisionDetail? _detail;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.fetch(widget.id);
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = _detail?.decision ?? widget.summary;
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
            if (decision == null)
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _Unavailable(onRetry: _load),
              )
            else
              ..._content(decision),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(DecisionSummary decision) {
    final detail = _detail;
    return [
      const SizedBox(height: 8),
      _VoteCard(decision: decision, count: detail?.count),
      const SizedBox(height: 24),
      _Meta(decision),
      const SizedBox(height: 8),
      Text(
        capitalize(decision.displayTitle),
        style: HemicycleText.detailTitle.copyWith(color: context.colors.ink),
      ),
      if (decision.explanation case final explanation?) ...[
        const SizedBox(height: 12),
        Text(
          explanation,
          style: TextStyle(
            fontSize: 16,
            height: 1.55,
            color: context.colors.body,
          ),
        ),
      ],
      // Résumé en points (#9) : dans le fichier de détail seulement.
      if (detail?.decision.summary?.points case final points?
          when points.isNotEmpty) ...[
        const SizedBox(height: 32),
        const _Heading(summaryPointsHeading),
        const SizedBox(height: 12),
        _SummaryPoints(points),
      ],
      if (detail != null)
        ..._groupSections(detail)
      else if (_loading)
        const Padding(
          padding: EdgeInsets.only(top: 32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: _Unavailable(onRetry: _load),
        ),
      const SizedBox(height: 28),
      _Facts(decision),
      const SizedBox(height: 28),
      _SourceLinks(decision),
      const SizedBox(height: 24),
      Text(
        sourceNotice,
        style: TextStyle(fontSize: 12, height: 1.5, color: context.colors.ink2),
      ),
    ];
  }

  List<Widget> _groupSections(DecisionDetail detail) => [
    // Décision provisoire (détection en direct, #10) : le site ne donne pas
    // le vote par groupe, le jeu de données du lendemain le complète.
    if (detail.groups.isEmpty &&
        detail.count != null &&
        detail.decision.status == DecisionStatus.provisoire) ...[
      const SizedBox(height: 32),
      const _Heading(groupsHeading),
      const SizedBox(height: 8),
      const _Muted(provisionalGroupsNotice),
    ],
    if (detail.groups.isNotEmpty) ...[
      const SizedBox(height: 32),
      const _Heading(groupsHeading),
      const SizedBox(height: 14),
      WhoVotedWhat(detail.groups),
    ],
    // Arguments des groupes (#35) : absents sans explications de vote.
    if (detail.arguments case final arguments?) ...[
      const SizedBox(height: 32),
      const _Heading(argumentsHeading),
      const SizedBox(height: 12),
      VoteArguments(arguments),
    ],
  ];
}

/// Intertitre des points du résumé.
const summaryPointsHeading = 'Ce que prévoit le texte';

/// Mention d'une décision sans scrutin public (ticket #8) : ni décompte ni
/// vote par groupe.
const mainLeveeNotice = 'Adopté à main levée, sans décompte des voix.';

/// « 570 députés ont voté » : pour, contre et abstentions.
String votersLabel(int total) =>
    total > 1 ? '$total députés ont voté' : '$total député a voté';

/// Vote par groupe d'une décision provisoire, pas encore publié.
const provisionalGroupsNotice =
    'Vote par groupe disponible après confirmation par les données '
    'officielles.';

/// Carte du vote : grand arc, mot du résultat au centre, puis les trois
/// chiffres (ou la mention « à main levée »).
class _VoteCard extends StatelessWidget {
  const _VoteCard({required this.decision, this.count});

  final DecisionSummary decision;

  /// Décompte complet du fichier de détail, s'il est arrivé ; sinon celui
  /// de l'index (sans les non-votants).
  final VoteCount? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tally = count?.tally ?? decision.count;
    final color = resultColor(context, decision.result);
    final mainLevee = decision.voteMode == VoteMode.mainLevee;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(280.0, constraints.maxWidth);
          return Column(
            children: [
              SizedBox(
                width: width,
                height: width * VoteArc.aspect,
                child: Stack(
                  children: [
                    VoteArc(
                      result: decision.result,
                      count: tally,
                      voteMode: decision.voteMode,
                      width: width,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LineIcon(
                            resultGlyph(decision.result),
                            size: 26,
                            strokeWidth: 2.4,
                            color: color,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            resultWord(decision.result),
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.6,
                              height: 1.15,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (mainLevee)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    mainLeveeNotice,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.ink2),
                  ),
                )
              else if (tally != null) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    _Figure(tally.pour, 'pour', colors.pour),
                    const SizedBox(width: 8),
                    _Figure(tally.contre, 'contre', colors.contre),
                    const SizedBox(width: 8),
                    _Figure(
                      tally.abstentions,
                      tally.abstentions > 1 ? 'abstentions' : 'abstention',
                      colors.ink2,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    votersLabel(tally.total),
                    style: TextStyle(fontSize: 13, color: colors.ink2),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Un des trois chiffres de la carte, en Geist Mono.
class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label, this.color);

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: HemicycleText.mono.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 13, color: context.colors.ink2)),
      ],
    ),
  );
}

/// « Scrutin public n° 8706 · 13 octobre 2026 · 1re lecture à l'AN ».
class _Meta extends StatelessWidget {
  const _Meta(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) => MetaLine(
    style: TextStyle(fontSize: 13, height: 1.4, color: context.colors.ink2),
    parts: [
      Text(switch (decision.numero) {
        final numero? when decision.voteMode == VoteMode.scrutinPublic =>
          'Scrutin public n° $numero',
        _ => 'Vote à main levée',
      }),
      Text(formatFrenchDate(decision.date)),
      if (decision.stage case final stage?) Text(stage),
    ],
    trailing: decision.status == DecisionStatus.provisoire
        ? const ProvisionalBadge()
        : null,
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: HemicycleText.heading.copyWith(color: context.colors.ink),
    ),
  );
}

/// Points du résumé, en liste à puces.
class _SummaryPoints extends StatelessWidget {
  const _SummaryPoints(this.points);

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: context.colors.body,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, point) in points.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 18, child: Text('•', style: style)),
                Expanded(child: Text(point, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Type de décision, statut et intitulé officiel.
class _Facts extends StatelessWidget {
  const _Facts(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Field(label: 'Type de décision', value: decisionTypeLabel(decision)),
      if (decision.status == DecisionStatus.provisoire)
        const _Field(
          label: 'Statut',
          value:
              'Provisoire : lu sur le site de l\'Assemblée, pas encore '
              'confirmé par les données officielles',
        ),
      _Field(
        label: 'Intitulé officiel',
        value: capitalize(decision.officialTitle),
      ),
    ],
  );
}

/// Libellé du type de décision.
String decisionTypeLabel(DecisionSummary decision) => switch (decision.type) {
  DecisionType.ensembleTexte => 'Vote sur l\'ensemble d\'un texte',
  DecisionType.motionDeCensure => 'Motion de censure',
  DecisionType.declarationGouvernement => 'Déclaration du Gouvernement',
  DecisionType.rejetPrealable => 'Motion de rejet préalable',
  DecisionType.premierePartieBudget => 'Vote sur la première partie du budget',
  DecisionType.resolution => 'Proposition de résolution',
  DecisionType.autre => 'Scrutin solennel',
};

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colors.ink2)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 14, height: 1.45, color: colors.body),
          ),
        ],
      ),
    );
  }
}

/// Liens vers les pages officielles : le scrutin, puis le dossier
/// législatif.
class _SourceLinks extends StatelessWidget {
  const _SourceLinks(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) {
    // Vote à main levée : `sourceUrl` est déjà la page du dossier.
    final mainLevee = decision.voteMode == VoteMode.mainLevee;
    final dossierUrl =
        decision.dossierUrl ?? (mainLevee ? decision.sourceUrl : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!mainLevee)
          ExternalLinkRow(label: 'Voir le scrutin', url: decision.sourceUrl),
        if (dossierUrl != null) ...[
          if (!mainLevee) const SizedBox(height: 8),
          ExternalLinkRow(
            label: 'Suivre le dossier législatif',
            url: dossierUrl,
          ),
        ],
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Impossible de charger le détail de cette décision.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: context.colors.ink2),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
    ],
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 14, height: 1.45, color: context.colors.ink2),
  );
}
