import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decision_list_page.dart' show capitalize, formatFrenchDate;
import '../theme.dart';
import 'decision_detail_repository.dart';
import 'vote_bar.dart';

/// Écran de détail d'une décision : titre court et intitulé officiel, type,
/// résultat, étape, date, décompte, vote par groupe et lien vers la source.
///
/// [summary] (la ligne de la liste) s'affiche tout de suite ; le fichier de
/// détail complète l'écran quand il arrive. Ouvert depuis un widget, seul
/// [id] est connu.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Décision')),
      body: decision == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : _Unavailable(onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Header(decision),
                const SizedBox(height: 24),
                if (_detail case final detail?)
                  ..._voteSections(detail)
                else if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _Unavailable(onRetry: _load, compact: true),
                const SizedBox(height: 24),
                _SourceLinks(decision),
              ],
            ),
    );
  }

  List<Widget> _voteSections(DecisionDetail detail) => [
    _Section(
      title: 'Décompte',
      child: switch (detail.count) {
        final count? => _Count(count),
        null => const _Muted(
          'Pas de scrutin public : texte adopté à main levée, sans décompte '
          'des voix.',
        ),
      },
    ),
    if (detail.groups.isNotEmpty) ...[
      const SizedBox(height: 24),
      _Section(
        title: 'Vote par groupe politique',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, group) in detail.groups.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _GroupRow(group),
            ],
          ],
        ),
      ),
    ],
  ];
}

/// Résultat, date, titre court, étape, type et intitulé officiel.
class _Header extends StatelessWidget {
  const _Header(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ResultBadge(decision.result),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formatFrenchDate(decision.date),
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          capitalize(decision.displayTitle),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (decision.stage case final stage?) ...[
          const SizedBox(height: 4),
          Text(
            stage,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 16),
        _Field(label: 'Type de décision', value: decisionTypeLabel(decision)),
        if (decision.status == DecisionStatus.provisoire)
          const _Field(
            label: 'Statut',
            value:
                'Provisoire : pas encore confirmé par les données officielles',
          ),
        _Field(
          label: 'Intitulé officiel',
          value: capitalize(decision.officialTitle),
        ),
      ],
    );
  }
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Barre pour / contre / abstention du scrutin et sa légende.
class _Count extends StatelessWidget {
  const _Count(this.count);

  final VoteCount count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VoteBar(count, height: 14),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Legend(color: VoteBar.pourColor, label: 'Pour', value: count.pour),
            _Legend(
              color: VoteBar.contreColor,
              label: 'Contre',
              value: count.contre,
            ),
            _Legend(
              color: VoteBar.abstentionColor(context),
              label: count.abstentions > 1 ? 'Abstentions' : 'Abstention',
              value: count.abstentions,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${count.votants} votants'
          '${count.nonVotants > 0 ? ' · ${count.nonVotants} non-votant${count.nonVotants > 1 ? 's' : ''}' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text('$label ', style: theme.textTheme.bodyMedium),
        Text(
          '$value',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Un groupe : nom, position et petite barre, sans couleur de parti.
class _GroupRow extends StatelessWidget {
  const _GroupRow(this.group);

  final GroupVoteDetail group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = group.count;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: group.name,
                    children: [
                      if (group.abbreviation case final abbreviation?)
                        TextSpan(
                          text: '  $abbreviation',
                          style: TextStyle(color: muted),
                        ),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                groupPositionLabel(group.position),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          VoteBar(c, height: 6),
          const SizedBox(height: 4),
          Text(
            '${c.pour} pour · ${c.contre} contre · '
            '${c.abstentions} abst.'
            '${c.nonVotants > 0 ? ' · ${c.nonVotants} non-votant${c.nonVotants > 1 ? 's' : ''}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// Libellé de la position d'un groupe.
String groupPositionLabel(GroupPosition position) => switch (position) {
  GroupPosition.pour => 'Pour',
  GroupPosition.contre => 'Contre',
  GroupPosition.abstention => 'Abstention',
  GroupPosition.partage => 'Partagé',
  GroupPosition.nonVotant => 'N\'a pas voté',
};

/// Liens vers les pages officielles : le dossier législatif (sinon le
/// scrutin), puis le scrutin.
class _SourceLinks extends StatelessWidget {
  const _SourceLinks(this.decision);

  final DecisionSummary decision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dossierUrl = decision.dossierUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _open(dossierUrl ?? decision.sourceUrl),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(
            dossierUrl != null
                ? 'Dossier sur le site de l\'Assemblée'
                : 'Scrutin sur le site de l\'Assemblée',
          ),
        ),
        if (dossierUrl != null)
          TextButton.icon(
            onPressed: () => _open(decision.sourceUrl),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('Scrutin n° ${decision.numero}'),
          ),
        const SizedBox(height: 8),
        Text(
          'Source : Assemblée nationale, open data. Licence Ouverte Etalab.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry, this.compact = false});

  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Impossible de charger le détail de cette décision.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    );
    return compact
        ? content
        : Center(
            child: Padding(padding: const EdgeInsets.all(24), child: content),
          );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Même badge que la liste (vert / brique, icône en plus de la couleur).
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
