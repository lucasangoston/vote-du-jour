import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decision_list_page.dart'
    show capitalize, formatShortFrenchDate, sourceNotice;
import '../hemicycle/external_link_row.dart';
import '../hemicycle/hemicycle_seats.dart';
import '../hemicycle/line_icon.dart';
import '../hemicycle/result_style.dart';
import '../hemicycle/vote_arc.dart';
import '../hemicycle/vote_glyph.dart';
import '../provisional_badge.dart';
import '../theme.dart';
import 'decision_detail_repository.dart';
import 'vote_arguments.dart';
import 'who_voted_what.dart';

/// Écran de détail d'une décision : carte du vote (hémicycle aux places
/// réelles ou grand arc, résultat, décompte), méta, titre, explication, points du résumé, « Qui a voté
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

  /// Groupe dont les sièges sont allumés (tuile touchée, #74).
  String? _lit;

  final _voteCardKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
        // Le contenu ne passe jamais sous la barre d'état, même en défilant.
        body: SafeArea(
          bottom: false,
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(20, 0, 20, 40 + padding.bottom),
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
      ),
    );
  }

  List<Widget> _content(DecisionSummary decision) {
    final detail = _detail;
    return [
      const SizedBox(height: 8),
      if (_seatsOf(detail) case (final detail, final count)?)
        _SeatsVoteCard(
          key: _voteCardKey,
          detail: detail,
          count: count,
          lit: _lit,
        )
      else
        _VoteCard(decision: decision, count: detail?.count),
      const SizedBox(height: 24),
      _Meta(decision),
      const SizedBox(height: 8),
      Text(
        capitalize(decision.displayTitle),
        style: HemicycleText.displayMd.copyWith(color: context.colors.ink),
      ),
      if (decision.explanation case final explanation?) ...[
        const SizedBox(height: 12),
        Text(
          explanation,
          style: HemicycleText.bodySerif.copyWith(color: context.colors.body),
        ),
      ],
      // Résumé en points (#9) : dans le fichier de détail seulement.
      if (detail?.decision.summary?.points case final points?
          when points.isNotEmpty) ...[
        const SizedBox(height: 32),
        const _Heading(summaryPointsHeading),
        const SizedBox(height: 12),
        SummaryPoints(points),
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
        style: HemicycleText.meta.copyWith(color: context.colors.ink2),
      ),
    ];
  }

  /// Le détail et son décompte s'il se dessine aux places réelles (#74) ;
  /// `null` sinon (ancien détail, provisoire, main levée, place inconnue) :
  /// la carte garde l'arc.
  (DecisionDetail, VoteCount)? _seatsOf(DecisionDetail? detail) {
    if (detail == null ||
        detail.decision.voteMode == VoteMode.mainLevee ||
        !canDrawSeats(detail.seats)) {
      return null;
    }
    final count = detail.count;
    return count == null ? null : (detail, count);
  }

  /// Allume les sièges du groupe, ou les rallume tous s'il l'était déjà ; en
  /// allumant, ramène l'hémicycle à l'écran.
  void _toggleGroup(GroupVoteDetail group) {
    final on = _lit != group.organeRef;
    setState(() => _lit = on ? group.organeRef : null);
    if (!on) return;
    const duration = Duration(milliseconds: 300);
    const curve = Curves.easeOutCubic;
    final card = _voteCardKey.currentContext;
    if (card != null) {
      Scrollable.ensureVisible(
        card,
        duration: duration,
        curve: curve,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    } else if (_scroll.hasClients) {
      // La carte, sortie de la liste paresseuse, n'est plus construite : elle
      // est en tête de l'écran.
      _scroll.animateTo(0, duration: duration, curve: curve);
    }
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
      WhoVotedWhat(
        detail.groups,
        selected: _lit,
        onSelect: _seatsOf(detail) == null ? null : _toggleGroup,
      ),
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
const mainLeveeNotice = 'À main levée · sans décompte des voix';

/// Vote par groupe d'une décision provisoire, pas encore publié.
const provisionalGroupsNotice = 'Vote par groupe publié après confirmation.';

/// Repères sous le grand arc dans l'ordre de l'hémicycle (#67).
const leftLabel = 'Gauche';
const rightLabel = 'Droite';

/// Carte du vote : grand arc, mot du résultat au centre, puis les trois
/// chiffres (ou la mention « à main levée »). Un arc dans l'ordre de
/// l'hémicycle (#67) porte en dessous les repères « Gauche » et « Droite ».
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
    final hemicycle = !mainLevee && decision.arc != null;
    // Surface douce à angle droit.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      color: colors.surface,
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
                      arc: decision.arc,
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
                            style: HemicycleText.displayLg.copyWith(
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Repères discrets, sous les extrémités de l'arc ; le libellé
              // accessible de l'arc donne déjà les totaux.
              if (hemicycle)
                ExcludeSemantics(
                  child: SizedBox(
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final label in [leftLabel, rightLabel])
                            Text(
                              label,
                              style: HemicycleText.meta.copyWith(
                                fontSize: 11,
                                color: colors.ink2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (mainLevee)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    mainLeveeNotice,
                    textAlign: TextAlign.center,
                    style: HemicycleText.meta.copyWith(color: colors.ink2),
                  ),
                )
              else if (tally != null) ...[
                SizedBox(height: hemicycle ? 12 : 18),
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
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Carte du vote aux places réelles (#74) : l'hémicycle, le résultat en
/// grand dessous (jamais dans le creux, il touchait le premier rang), puis
/// les trois chiffres, chacun avec le symbole de sa forme dans l'hémicycle.
class _SeatsVoteCard extends StatelessWidget {
  const _SeatsVoteCard({
    super.key,
    required this.detail,
    required this.count,
    this.lit,
  });

  final DecisionDetail detail;
  final VoteCount count;
  final String? lit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = detail.decision.result;
    final tally = count.tally;
    // Surface douce à angle droit.
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(340.0, constraints.maxWidth);
          return Column(
            children: [
              HemicycleSeats(
                seats: detail.seats!,
                groups: detail.groups,
                result: result,
                count: tally,
                width: width,
                lit: lit,
              ),
              const SizedBox(height: 14),
              Text(
                resultWord(result),
                style: HemicycleText.displayLg.copyWith(
                  color: resultColor(context, result),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _Figure(
                    tally.pour,
                    'pour',
                    colors.pour,
                    glyph: VotePosition.pour,
                  ),
                  const SizedBox(width: 8),
                  _Figure(
                    tally.contre,
                    'contre',
                    colors.contre,
                    glyph: VotePosition.contre,
                  ),
                  const SizedBox(width: 8),
                  _Figure(
                    tally.abstentions,
                    tally.abstentions > 1 ? 'abstentions' : 'abstention',
                    colors.ink,
                    glyph: VotePosition.abstention,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              NoVoteNote(detail.seats!),
            ],
          );
        },
      ),
    );
  }
}

/// Un des trois chiffres de la carte, en Geist à chiffres tabulaires
/// (`figure`). Avec [glyph], le libellé est précédé du symbole du vote (forme
/// des sièges) ; sans, le chiffre est un peu plus petit, sous le grand arc.
class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label, this.color, {this.glyph});

  final int value;
  final String label;
  final Color color;
  final VotePosition? glyph;

  @override
  Widget build(BuildContext context) {
    final ink2 = context.colors.ink2;
    final text = Text(label, style: HemicycleText.meta.copyWith(color: ink2));
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: HemicycleText.figure.copyWith(
              fontSize: glyph == null ? 22 : null,
              color: color,
            ),
          ),
          if (glyph case final glyph?)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                VoteGlyph(glyph, color: ink2),
                const SizedBox(width: 5),
                Flexible(child: text),
              ],
            )
          else
            text,
        ],
      ),
    );
  }
}

/// « Scrutin n° 8706 · 13 oct. 2026 · 1re lecture » ; « 13 oct. 2026 ·
/// 1re lecture » pour un vote à main levée (la carte le dit déjà).
class _Meta extends StatelessWidget {
  const _Meta(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) => MetaLine(
    style: HemicycleText.meta.copyWith(color: context.colors.ink2),
    parts: [
      if (decision.numero case final numero?
          when decision.voteMode == VoteMode.scrutinPublic)
        Text('Scrutin n° $numero'),
      Text(formatShortFrenchDate(decision.date)),
      if (decision.stage case final stage?) Text(shortStage(stage)),
    ],
    trailing: decision.status == DecisionStatus.provisoire
        ? const ProvisionalBadge()
        : null,
  );
}

/// Étape sans « à l'AN », implicite dans l'app : « 1re lecture à l'AN »
/// devient « 1re lecture ».
String shortStage(String stage) => stage.replaceAll(" à l'AN", '');

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

/// Points du résumé, en liste à puces (détail, écran « En débat »).
class SummaryPoints extends StatelessWidget {
  const SummaryPoints(this.points, {super.key});

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final style = HemicycleText.bodySerif.copyWith(color: context.colors.body);
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

/// Intitulé officiel du scrutin (le type et le statut sont déjà dans la
/// méta).
class _Facts extends StatelessWidget {
  const _Facts(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) => _Field(
    label: 'Texte officiel',
    value: capitalize(decision.officialTitle),
  );
}

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
          Text(label, style: HemicycleText.meta.copyWith(color: colors.ink2)),
          const SizedBox(height: 2),
          Text(
            value,
            style: HemicycleText.bodySmall.copyWith(color: colors.body),
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
    return RuledRows(
      children: [
        if (!mainLevee)
          ExternalLinkRow(label: 'Voir le scrutin', url: decision.sourceUrl),
        if (dossierUrl != null)
          ExternalLinkRow(label: 'Dossier législatif', url: dossierUrl),
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
        'Détail indisponible.',
        textAlign: TextAlign.center,
        style: HemicycleText.bodySmall.copyWith(color: context.colors.ink2),
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
    style: HemicycleText.bodySmall.copyWith(color: context.colors.ink2),
  );
}
