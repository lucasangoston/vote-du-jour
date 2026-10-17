import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import 'decisions_repository.dart';
import 'discovery_actions.dart';
import 'theme.dart';

/// Liste des dernières décisions. Se rafraîchit à l'ouverture et à chaque
/// retour de l'app au premier plan.
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
          const SnackBar(content: Text('Actualisation impossible.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Décisions de l\'Assemblée'),
        actions: const [AddWidgetAction(), AboutAction()],
      ),
      body: _body(context),
      bottomNavigationBar: const _SourceNotice(),
    );
  }

  Widget _body(BuildContext context) {
    final index = _index;
    if (index == null) {
      if (_error != null && !_loading) {
        return _Message(
          text: 'Impossible de charger les décisions.',
          action: FilledButton.tonal(
            onPressed: _refresh,
            child: const Text('Réessayer'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (index.decisions.isEmpty) {
      return const _Message(text: 'Aucune décision publiée pour le moment.');
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: index.decisions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _DecisionTile(index.decisions[i]),
      ),
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ResultBadge(decision.result),
              const SizedBox(width: 12),
              Text(
                formatFrenchDate(decision.date),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            capitalize(decision.officialTitle),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge(this.result);

  final VoteResult result;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (result) {
      VoteResult.adopte => ('Adopté', Icons.check, ResultColors.adopted),
      VoteResult.rejete => ('Rejeté', Icons.close, ResultColors.rejected),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mention de la source exigée par la Licence Ouverte.
class _SourceNotice extends StatelessWidget {
  const _SourceNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          'Source : Assemblée nationale, open data (data.assemblee-nationale.fr). '
          'Licence Ouverte Etalab. Application indépendante, non officielle.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

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
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// « 13 octobre 2026 » (« 1er » pour le premier du mois).
String formatFrenchDate(DateTime date) {
  final day = date.day == 1 ? '1er' : '${date.day}';
  return '$day ${_months[date.month - 1]} ${date.year}';
}

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
