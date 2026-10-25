import 'package:flutter/material.dart';

import '../theme.dart';
import 'important_votes_notifications.dart';

/// Réglage « Notifier les votes solennels » de la page À propos : ligne à
/// interrupteur, à poser dans un panneau. Absent si les notifications ne
/// sont pas disponibles.
class ImportantVotesSetting extends StatefulWidget {
  const ImportantVotesSetting({super.key});

  @override
  State<ImportantVotesSetting> createState() => _ImportantVotesSettingState();
}

class _ImportantVotesSettingState extends State<ImportantVotesSetting> {
  AppLifecycleListener? _lifecycle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifications = NotificationsScope.maybeOf(context);
    if (notifications != null && _lifecycle == null) {
      // L'autorisation a pu changer dans les réglages du téléphone.
      notifications.refreshPermission();
      _lifecycle = AppLifecycleListener(
        onResume: () =>
            NotificationsScope.maybeOf(context)?.refreshPermission(),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = NotificationsScope.maybeOf(context);
    if (notifications == null) return const SizedBox.shrink();
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final refused = notifications.refused;
    // Toute la ligne bascule le réglage, comme une ligne de réglages.
    return MergeSemantics(
      child: InkWell(
        onTap: refused
            ? null
            : () => notifications.setEnabled(!notifications.enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifier les votes solennels',
                      style: HemicycleText.label.copyWith(color: colors.ink),
                    ),
                    if (refused) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Notifications refusées : activez-les dans les '
                        'Réglages.',
                        style: HemicycleText.meta.copyWith(
                          color: colors.contre,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Piste à l'encre une fois activé, comme dans la maquette ;
              // pastille blanche, noire (le fond) en Nuit.
              Switch.adaptive(
                value: notifications.enabled,
                activeTrackColor: colors.ink,
                inactiveTrackColor: colors.raised,
                trackOutlineColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                thumbColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) && dark
                      ? colors.background
                      : colors.plate,
                ),
                onChanged: refused ? null : notifications.setEnabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
