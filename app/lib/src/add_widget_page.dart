import 'package:flutter/material.dart';

import 'app_identity.dart';

enum WidgetPlatform { ios, android }

/// Explique comment ajouter le widget à l'écran d'accueil. Les étapes de la
/// plateforme courante sont affichées d'abord ; l'autre reste consultable.
class AddWidgetPage extends StatefulWidget {
  const AddWidgetPage({super.key});

  @override
  State<AddWidgetPage> createState() => _AddWidgetPageState();
}

class _AddWidgetPageState extends State<AddWidgetPage> {
  WidgetPlatform? _selected;

  WidgetPlatform _platformOf(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => WidgetPlatform.ios,
        _ => WidgetPlatform.android,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = _selected ?? _platformOf(context);
    final steps = switch (platform) {
      WidgetPlatform.ios => iosSteps,
      WidgetPlatform.android => androidSteps,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter le widget')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Le widget affiche les dernières décisions de l\'Assemblée '
            'directement sur votre écran d\'accueil, sans ouvrir l\'app.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          SegmentedButton<WidgetPlatform>(
            segments: const [
              ButtonSegment(
                value: WidgetPlatform.ios,
                label: Text('iPhone'),
                icon: Icon(Icons.phone_iphone),
              ),
              ButtonSegment(
                value: WidgetPlatform.android,
                label: Text('Android'),
                icon: Icon(Icons.phone_android),
              ),
            ],
            selected: {platform},
            onSelectionChanged: (s) => setState(() => _selected = s.single),
          ),
          const SizedBox(height: 20),
          for (final (i, step) in steps.indexed)
            _Step(number: i + 1, text: step, last: i == steps.length - 1),
          const SizedBox(height: 12),
          Text(
            'Trois tailles existent : petite (la dernière décision), moyenne '
            '(la dernière décision avec son explication) et grande (les trois '
            'dernières décisions). Touchez une décision pour ouvrir son '
            'détail.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
const iosSteps = [
  'Sur l\'écran d\'accueil, faites un appui long sur une zone vide, '
      'jusqu\'à ce que les icônes se mettent à trembler.',
  'Touchez « Modifier » en haut de l\'écran, puis « Ajouter un widget ».',
  'Recherchez « $appName » et touchez l\'app dans les résultats.',
  'Balayez pour choisir une taille, puis touchez « Ajouter le widget ».',
  'Placez le widget où vous le souhaitez, puis touchez « OK ».',
];

@visibleForTesting
const androidSteps = [
  'Sur l\'écran d\'accueil, faites un appui long sur une zone vide.',
  'Touchez « Widgets ».',
  'Recherchez « $appName » dans la liste et touchez l\'app.',
  'Maintenez le widget de la taille souhaitée, puis faites-le glisser sur '
      'l\'écran d\'accueil.',
];

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text, required this.last});

  final int number;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: scheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: last ? 8 : 20),
              child: Text(text, style: theme.textTheme.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}
