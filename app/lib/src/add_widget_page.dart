import 'package:flutter/material.dart';

import 'app_identity.dart';
import 'hemicycle/external_link_row.dart';
import 'theme.dart';

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
    final colors = context.colors;
    final platform = _selected ?? _platformOf(context);
    final steps = switch (platform) {
      WidgetPlatform.ios => iosSteps,
      WidgetPlatform.android => androidSteps,
    };
    return HemicyclePage(
      title: 'Ajouter le widget',
      children: [
        Text(
          'Le widget affiche les dernières décisions de l\'Assemblée '
          'directement sur votre écran d\'accueil, sans ouvrir l\'app.',
          style: TextStyle(fontSize: 16, height: 1.55, color: colors.body),
        ),
        const SizedBox(height: 20),
        SegmentedButton<WidgetPlatform>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: WidgetPlatform.ios, label: Text('iPhone')),
            ButtonSegment(
              value: WidgetPlatform.android,
              label: Text('Android'),
            ),
          ],
          selected: {platform},
          onSelectionChanged: (s) => setState(() => _selected = s.single),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              for (final (i, step) in steps.indexed)
                _Step(number: i + 1, text: step, last: i == steps.length - 1),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Trois tailles existent : petite (la dernière décision), moyenne '
          '(la dernière décision avec son explication) et grande (les trois '
          'dernières décisions). Touchez une décision pour ouvrir son '
          'détail.',
          style: TextStyle(fontSize: 14, height: 1.5, color: colors.ink2),
        ),
      ],
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
    final colors = context.colors;
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
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.rule, width: 1.5),
                ),
                child: Text(
                  '$number',
                  style: HemicycleText.mono.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.ink,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: colors.rule,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: last ? 8 : 20),
              child: Text(
                text,
                style: TextStyle(fontSize: 15, height: 1.5, color: colors.body),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
