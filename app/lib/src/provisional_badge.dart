import 'package:flutter/material.dart';

import 'decision_status_label.dart';

/// Badge discret « provisoire » : décision lue sur le site de l'Assemblée
/// pendant la séance, confirmée le lendemain par le jeu de données officiel.
class ProvisionalBadge extends StatelessWidget {
  const ProvisionalBadge({super.key});

  static const explanation =
      'Pas encore confirmé par les données officielles (en général le '
      'lendemain).';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: explanation,
      triggerMode: TooltipTriggerMode.tap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 7, 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                provisionalLabel,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
