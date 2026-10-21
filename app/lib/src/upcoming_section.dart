import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vote_contract/vote_contract.dart';

import 'hemicycle/line_icon.dart';
import 'hemicycle/result_style.dart';
import 'relative_date.dart';
import 'theme.dart';

/// Section « À venir » en tête de la liste (#53) : les prochains points de
/// l'ordre du jour de l'Assemblée (bloc `upcoming` de l'index), dans l'ordre
/// chronologique, [collapsedCount] au plus puis « Tout voir ».
///
/// Rien n'est affiché sans point à venir (ancien index sans `upcoming`, ou
/// points tous passés dans un index relu hors ligne).
class UpcomingSection extends StatefulWidget {
  const UpcomingSection({super.key, required this.items, this.now});

  final List<UpcomingItem>? items;

  /// Instant de référence (tests) ; par défaut, l'heure courante.
  final DateTime? now;

  /// Nombre de points affichés avant « Tout voir ».
  static const collapsedCount = 3;

  @override
  State<UpcomingSection> createState() => _UpcomingSectionState();
}

class _UpcomingSectionState extends State<UpcomingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final items = upcomingToShow(widget.items, now: now);
    if (items.isEmpty) return const SizedBox.shrink();
    final collapsed =
        !_expanded && items.length > UpcomingSection.collapsedCount;
    final shown = collapsed
        ? items.take(UpcomingSection.collapsedCount).toList()
        : items;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              header: true,
              child: Text(
                'À venir',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.ink2,
                ),
              ),
            ),
          ),
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, item) in shown.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 16, color: colors.rule),
                  UpcomingRow(item, now: now),
                ],
                if (collapsed) ...[
                  Divider(height: 1, color: colors.rule),
                  _ShowAllButton(
                    onPressed: () => setState(() => _expanded = true),
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

/// Points à afficher : ceux d'aujourd'hui (heure de Paris) ou plus tard,
/// dans l'ordre chronologique (ordre de l'index à heure égale).
List<UpcomingItem> upcomingToShow(
  List<UpcomingItem>? items, {
  required DateTime now,
}) {
  if (items == null || items.isEmpty) return const [];
  final today = parisDay(now);
  final indexed = [
    for (final (i, item) in items.indexed)
      if (!parisDay(item.startsAt).isBefore(today)) (i, item),
  ];
  indexed.sort((a, b) {
    final byTime = a.$2.startsAt.compareTo(b.$2.startsAt);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}

/// Ligne d'un point à venir : jour et heure de début de séance, badge
/// « Vote solennel » ou mention « En discussion », titre court. Le tap
/// ouvre le dossier législatif.
class UpcomingRow extends StatelessWidget {
  const UpcomingRow(this.item, {super.key, required this.now});

  final UpcomingItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final day = upcomingDayLabel(item.startsAt, now: now);
    // La séance commence à cette heure ; le point vient ensuite.
    final time = 'à partir de ${parisHourLabel(item.startsAt)}';
    final vote = item.kind == UpcomingKind.voteSolennel;
    final inDiscussion = !vote && item.inProgress;
    final url = item.dossierUrl;
    final semanticsLabel = [
      upcomingDayLabel(item.startsAt, now: now, long: true),
      time,
      if (vote) 'vote solennel',
      if (inDiscussion) 'en discussion',
      item.shortTitle,
    ].join(', ');
    return Semantics(
      link: url != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: url == null
            ? null
            : () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetaLine(
                      style: TextStyle(fontSize: 12.5, color: colors.ink2),
                      parts: [
                        Text(
                          day,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.ink,
                          ),
                        ),
                        Text(time),
                        if (inDiscussion) const Text('En discussion'),
                      ],
                      trailing: vote ? const _VoteBadge() : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.shortTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HemicycleText.rowTitle.copyWith(
                        fontSize: 15,
                        color: colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (url != null) ...[
                const SizedBox(width: 12),
                LineIcon(
                  LineGlyph.external,
                  size: 18,
                  strokeWidth: 1.8,
                  color: colors.ink2,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge « Vote solennel » : filet et encre, sans couleur (le résultat n'est
/// pas encore connu).
class _VoteBadge extends StatelessWidget {
  const _VoteBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.ink2.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          'Vote solennel',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
      ),
    );
  }
}

class _ShowAllButton extends StatelessWidget {
  const _ShowAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 0),
        child: Center(
          child: Text(
            'Tout voir',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colors.ink2,
            ),
          ),
        ),
      ),
    ),
  );
}
