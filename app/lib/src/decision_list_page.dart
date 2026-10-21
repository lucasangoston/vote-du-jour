import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vote_contract/vote_contract.dart';

import 'app_identity.dart';
import 'decision_detail/decision_route.dart';
import 'decisions_repository.dart';
import 'discovery_actions.dart';
import 'hemicycle/hemicycle_logo.dart';
import 'hemicycle/result_style.dart';
import 'hemicycle/vote_arc.dart';
import 'provisional_badge.dart';
import 'relative_date.dart';
import 'theme.dart';
import 'upcoming_section.dart';
import 'vote_mode_label.dart';

export 'relative_date.dart' show formatShortFrenchDate;

/// Liste des dernières décisions, groupées par jour. Se rafraîchit à
/// l'ouverture et à chaque retour de l'app au premier plan.
class DecisionListPage extends StatefulWidget {
  const DecisionListPage({super.key, required this.repository});

  final DecisionsRepository repository;

  @override
  State<DecisionListPage> createState() => _DecisionListPageState();
}

class _DecisionListPageState extends State<DecisionListPage> {
  late final AppLifecycleListener _lifecycle;
  DecisionIndex? _index;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    // Hors ligne : afficher d'abord les dernières données connues.
    if (_index == null) {
      final cached = await widget.repository.readCached();
      if (mounted && cached != null && _index == null) {
        setState(() => _index = cached);
      }
    }
    try {
      final index = await widget.repository.fetchLatest();
      if (!mounted) return;
      setState(() {
        _index = index;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (_index != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hors ligne : dernières données connues.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),
              ..._body(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final index = _index;
    if (index == null) {
      if (_error != null && !_loading) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              text: 'Impossible de charger les décisions.',
              action: FilledButton(
                onPressed: _refresh,
                child: const Text('Réessayer'),
              ),
            ),
          ),
        ];
      }
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    // Ordre du jour de l'Assemblée, avant les décisions (#53) ; rien sans
    // point à venir.
    final upcoming = SliverToBoxAdapter(
      child: UpcomingSection(items: index.upcoming),
    );
    if (index.decisions.isEmpty) {
      return [
        upcoming,
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(text: 'Aucune décision publiée pour le moment.'),
        ),
      ];
    }
    final now = DateTime.now();
    return [
      upcoming,
      for (final day in groupByDay(index.decisions)) ...[
        SliverToBoxAdapter(
          child: _DayHeading(dayGroupLabel(day.first.date, now: now)),
        ),
        SliverList.separated(
          itemCount: day.length,
          separatorBuilder: (_, _) => const _RowSeparator(),
          // Le tap ouvre le détail de la décision.
          itemBuilder: (context, i) =>
              OpenDecisionOnTap(decision: day[i], child: DecisionRow(day[i])),
        ),
      ],
      const SliverToBoxAdapter(child: _SourceNotice()),
    ];
  }
}

/// Décisions groupées par jour de vote, dans l'ordre de l'index.
List<List<DecisionSummary>> groupByDay(List<DecisionSummary> decisions) {
  final days = <List<DecisionSummary>>[];
  for (final d in decisions) {
    final last = days.lastOrNull?.first.date;
    if (last != null &&
        last.year == d.date.year &&
        last.month == d.date.month &&
        last.day == d.date.day) {
      days.last.add(d);
    } else {
      days.add([d]);
    }
  }
  return days;
}

/// Logo et nom, boutons « Ajouter le widget » et « À propos », grand titre.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 10),
            child: Row(
              children: [
                const HemicycleLogo.small(),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    appName,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const AddWidgetAction(),
                const AboutAction(),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text('Décisions', style: HemicycleText.largeTitle),
          ),
        ],
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.colors.ink2,
        ),
      ),
    ),
  );
}

class _RowSeparator extends StatelessWidget {
  const _RowSeparator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 74, right: 20),
    child: Divider(height: 1, color: context.colors.rule),
  );
}

/// Ligne de la liste : mini-arc du vote, résultat coloré · type (s'il change
/// la lecture), titre et phrase d'explication sur deux lignes.
class DecisionRow extends StatelessWidget {
  const DecisionRow(this.decision, {super.key});

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: VoteArc.mini(
              result: decision.result,
              count: decision.count,
              voteMode: decision.voteMode,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MetaLine(
                  style: TextStyle(fontSize: 12.5, color: colors.ink2),
                  parts: [
                    Text(
                      resultWord(decision.result),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: resultColor(context, decision.result),
                      ),
                    ),
                    // Pas l'étape de la procédure (détail seulement) : le
                    // type, quand il change la lecture du résultat.
                    if (listTypeLabel(decision.type) case final type?)
                      Text(type),
                    // Adopté sans scrutin public, donc sans décompte (#8).
                    if (voteModeLabel(decision.voteMode) case final mode?)
                      Text(mode),
                  ],
                  // Lue pendant la séance, pas encore confirmée (#10).
                  trailing: decision.status == DecisionStatus.provisoire
                      ? const ProvisionalBadge()
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  capitalize(decision.displayTitle),
                  style: HemicycleText.rowTitle.copyWith(color: colors.ink),
                ),
                // Phrase d'explication du résumé (#9), si la décision est
                // résumée.
                if (decision.explanation case final explanation?) ...[
                  const SizedBox(height: 4),
                  Text(
                    explanation,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: colors.ink2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Type de la décision dans la ligne de la liste, pour ceux qui changent la
/// lecture du résultat (une résolution n'a pas valeur de loi, un rejet
/// préalable rejette le texte…) ; `null` pour un vote sur un texte.
String? listTypeLabel(DecisionType type) => switch (type) {
  DecisionType.resolution => 'Résolution',
  DecisionType.motionDeCensure => 'Motion de censure',
  DecisionType.rejetPrealable => 'Rejet préalable',
  DecisionType.declarationGouvernement => 'Déclaration du Gouvernement',
  DecisionType.premierePartieBudget => '1re partie du budget',
  DecisionType.ensembleTexte || DecisionType.autre => null,
};

/// Mention de la source exigée par la Licence Ouverte.
class _SourceNotice extends StatelessWidget {
  const _SourceNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      28,
      20,
      24 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Text(
      sourceNotice,
      style: TextStyle(fontSize: 12, height: 1.5, color: context.colors.ink2),
    ),
  );
}

/// Mention de la source, en bas de la liste et du détail.
const sourceNotice =
    'Source : Assemblée nationale (open data, Licence Ouverte). '
    'App non officielle.';

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: context.colors.ink2),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
