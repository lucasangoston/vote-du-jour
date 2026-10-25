import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vote_contract/vote_contract.dart';

import 'decision_detail/decision_route.dart';
import 'decisions_repository.dart';
import 'discovery_actions.dart';
import 'hemicycle/line_icon.dart';
import 'hemicycle/result_style.dart';
import 'hemicycle/vote_arc.dart';
import 'provisional_badge.dart';
import 'relative_date.dart';
import 'theme.dart';

export 'relative_date.dart' show formatShortFrenchDate;

/// Liste des dernières décisions, groupées par jour, ouverte par « Toutes
/// les décisions » de l'accueil (#79). Se rafraîchit à l'ouverture et à
/// chaque retour de l'app au premier plan.
class DecisionListPage extends StatefulWidget {
  const DecisionListPage({super.key, required this.repository, this.initial});

  final DecisionsRepository repository;

  /// Index déjà lu par l'accueil, affiché pendant le rafraîchissement.
  final DecisionIndex? initial;

  @override
  State<DecisionListPage> createState() => _DecisionListPageState();
}

class _DecisionListPageState extends State<DecisionListPage> {
  late final AppLifecycleListener _lifecycle;
  late DecisionIndex? _index = widget.initial;
  Object? _error;
  bool _loading = false;
  DecisionFilter _filter = DecisionFilter.tout;

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
        // Le contenu ne passe jamais sous la barre d'état, même en défilant.
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _Header()),
                ..._body(context),
              ],
            ),
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
    // Plus de section « À venir » (maquette `liste`, #89) : le prochain vote
    // solennel est une carte de l'accueil, le texte en débat une
    // notification (#77).
    if (index.decisions.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(text: 'Aucune décision publiée pour le moment.'),
        ),
      ];
    }
    final now = DateTime.now();
    final shown = [
      for (final d in index.decisions)
        if (_filter.accepts(d.type)) d,
    ];
    return [
      // Filtres par type (#75), au-dessus des décisions qu'ils trient.
      SliverToBoxAdapter(
        child: _FilterChips(
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
      ),
      if (shown.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 24),
            child: _Message(text: 'Aucune décision de ce type récemment.'),
          ),
        ),
      for (final day in groupByDay(shown)) ...[
        SliverToBoxAdapter(
          child: _DayHeading(dayGroupLabel(day.first.date, now: now)),
        ),
        // Rangées sur le fond, un filet de 1 point sous chacune.
        SliverList.builder(
          itemCount: day.length,
          // Le tap ouvre le détail de la décision.
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpenDecisionOnTap(decision: day[i], child: DecisionRow(day[i])),
                const Divider(),
              ],
            ),
          ),
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

/// Retour à l'accueil et « À propos » (la barre de l'accueil si la liste
/// est le premier écran), grand titre.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Navigator.of(context).canPop())
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 10),
              child: Row(
                children: [
                  Expanded(child: HemicycleBackButton()),
                  AboutAction(),
                ],
              ),
            )
          else
            const BrandBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text(
              'Décisions',
              style: HemicycleText.displayLg.copyWith(
                color: context.colors.ink,
              ),
            ),
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
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            label,
            style: HemicycleText.meta.copyWith(color: context.colors.ink2),
          ),
        ),
        const SizedBox(height: 10),
        // Filet au-dessus de la première rangée du jour.
        const Divider(),
      ],
    ),
  );
}

/// Ligne de la liste (#75) : jauge du vote, titre (court s'il existe) et
/// « Adopté » ou « Rejeté » seul, sans chiffres ni type.
class DecisionRow extends StatelessWidget {
  const DecisionRow(this.decision, {super.key});

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: VoteGauge(
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
                Text(
                  capitalize(decision.compactTitle),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: HemicycleText.bodyStrong.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 6),
                MetaLine(
                  style: HemicycleText.meta,
                  parts: [
                    Text(
                      resultWord(decision.result),
                      style: HemicycleText.labelStrong.copyWith(
                        color: resultColor(context, decision.result),
                      ),
                    ),
                  ],
                  // Lue pendant la séance, pas encore confirmée (#10).
                  trailing: decision.status == DecisionStatus.provisoire
                      ? const ProvisionalBadge()
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtres de la liste (#75), comme les maquettes : les textes, les
/// résolutions, et les motions et votes sur le Gouvernement.
enum DecisionFilter {
  tout('Tout'),
  textes('Textes'),
  resolutions('Résolutions'),
  motions('Motions');

  const DecisionFilter(this.label);

  final String label;

  /// La décision de type [type] passe-t-elle le filtre ?
  bool accepts(DecisionType type) => switch (this) {
    tout => true,
    textes => switch (type) {
      DecisionType.ensembleTexte ||
      DecisionType.premierePartieBudget ||
      DecisionType.autre => true,
      _ => false,
    },
    resolutions => type == DecisionType.resolution,
    motions => switch (type) {
      DecisionType.motionDeCensure ||
      DecisionType.rejetPrealable ||
      DecisionType.declarationGouvernement => true,
      _ => false,
    },
  };
}

/// Filtres : rectangles au filet, le choix en encre pleine ; défilent si
/// l'écran est étroit.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final DecisionFilter selected;
  final ValueChanged<DecisionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
      child: Row(
        children: [
          for (final (i, f) in DecisionFilter.values.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Semantics(
              button: true,
              selected: f == selected,
              child: Material(
                color: f == selected ? colors.ink : colors.background,
                shape: Border.all(
                  color: f == selected ? colors.ink : colors.rule,
                ),
                child: InkWell(
                  onTap: () => onSelected(f),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    child: Text(
                      f.label,
                      style: HemicycleText.control.copyWith(
                        color: f == selected ? colors.background : colors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
      style: HemicycleText.meta.copyWith(color: context.colors.ink2),
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
              style: HemicycleText.bodySmall.copyWith(
                color: context.colors.ink2,
              ),
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
