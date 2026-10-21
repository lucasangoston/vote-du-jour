import 'package:flutter/material.dart';

import '../theme.dart';
import 'important_votes_notifications.dart';

/// Réglage « Votes importants » de la page À propos :
/// interrupteur et explication. Absent si les notifications ne sont pas
/// disponibles.
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
    final refused = notifications.refused;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toute la ligne bascule le réglage, comme une ligne de réglages.
            MergeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: refused
                    ? null
                    : () => notifications.setEnabled(!notifications.enabled),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Votes importants',
                        style: HemicycleText.rowTitle.copyWith(
                          color: colors.ink,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: notifications.enabled,
                      activeTrackColor: colors.pour,
                      onChanged: refused ? null : notifications.setEnabled,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Solennels, censures, textes de compromis et lectures '
                'définitives · 1 à 3 par semaine.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colors.ink2,
                ),
              ),
            ),
            if (refused) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'Notifications refusées : activez-les dans les Réglages.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: colors.contre,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
