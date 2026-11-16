import 'package:flutter/material.dart';

import 'package:vote_contract/vote_contract.dart';

import 'decision_status_label.dart';

/// Vote par groupe d'une décision provisoire, pas encore publié.
const provisionalGroupsNotice = 'Vote par groupe publié après confirmation.';

/// Décision lue sur le site pendant la séance (#10) : le décompte est connu,
/// pas encore le vote de chaque député. Ses sièges se dessinent en gris,
/// comme l'hémicycle d'un texte en débat, jamais en arc par camp, qui
/// ressemblerait à une autre figure que l'hémicycle.
bool isProvisionalScrutin(DecisionSummary d) =>
    d.status == DecisionStatus.provisoire &&
    d.voteMode == VoteMode.scrutinPublic;

/// Badge discret « provisoire », rectangle au filet : décision lue sur le site de l'Assemblée
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
