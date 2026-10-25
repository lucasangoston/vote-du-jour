import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add_widget_page.dart';
import 'app_identity.dart';
import 'appearance.dart';
import 'hemicycle/external_link_row.dart';
import 'hemicycle/hemicycle_logo.dart';
import 'hemicycle/line_icon.dart';
import 'hemicycle/vote_glyph.dart';
import 'notifications/important_votes_notifications.dart';
import 'notifications/important_votes_setting.dart';
import 'theme.dart';

const _openDataUrl = 'https://data.assemblee-nationale.fr';
const _supportUrl = 'https://lucasangoston.github.io/vote-du-jour/support.html';
const _privacyUrl =
    'https://lucasangoston.github.io/vote-du-jour/confidentialite.html';

/// Page « À propos » réduite (#76), d'après la maquette `apropos` : logo et
/// nom, apparence, réglages, légende des symboles de vote, liens et mention
/// des résumés par IA.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notifications = NotificationsScope.maybeOf(context) != null;
    return HemicyclePage(
      title: 'À propos',
      children: [
        // Logo et nom, comme sur la planche d'identité : surface douce à
        // angle droit.
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
          color: colors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HemicycleLogo.large(width: 88),
              const SizedBox(height: 14),
              Text(
                appName,
                style: HemicycleText.labelStrong.copyWith(
                  fontSize: 24,
                  letterSpacing: -0.48,
                  color: colors.ink,
                ),
              ),
            ],
          ),
        ),
        const _Group(padded: true, children: [AppearanceSelector()]),
        _Group(
          children: [
            // Le réglage n'existe que si les notifications sont disponibles.
            if (notifications) const ImportantVotesSetting(),
            _PanelRow(
              label: 'Ajouter le widget',
              glyph: LineGlyph.chevron,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AddWidgetPage()),
              ),
            ),
          ],
        ),
        const _Group(padded: true, children: [_VoteKey()]),
        _Group(
          children: [
            for (final (label, url) in const [
              ('Données de l’Assemblée nationale', _openDataUrl),
              ('Contact', _supportUrl),
              ('Confidentialité', _privacyUrl),
            ])
              _PanelRow(
                label: label,
                glyph: LineGlyph.external,
                link: true,
                onTap: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Résumés écrits par une IA. Seul le texte officiel fait foi. '
          'Application non officielle.',
          style: HemicycleText.meta.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}

/// Sélecteur d'apparence Auto / Jour / Nuit : rectangle au filet d'encre,
/// le choix en encre pleine.
class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({super.key});

  static const _options = [
    (ThemeMode.system, 'Auto'),
    (ThemeMode.light, 'Jour'),
    (ThemeMode.dark, 'Nuit'),
  ];

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.maybeOf(context);
    if (appearance == null) return const SizedBox.shrink();
    final colors = context.colors;
    return Semantics(
      label: 'Apparence',
      container: true,
      // Le filet par-dessus les segments, que leur fond ne masque pas.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border.all(color: colors.ink)),
        child: Row(
          children: [
            for (final (mode, label) in _options)
              Expanded(
                child: _Segment(
                  label: label,
                  selected: appearance.mode == mode,
                  onTap: () => appearance.setMode(mode),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? colors.ink : colors.background,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(
                label,
                style: HemicycleText.control.copyWith(
                  color: selected ? colors.background : colors.ink2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Légende des trois symboles de vote, centrée.
class _VoteKey extends StatelessWidget {
  const _VoteKey();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget entry(VotePosition position, String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VoteGlyph(position, color: color),
        const SizedBox(width: 4),
        Text(label, style: HemicycleText.bodySmall.copyWith(color: color)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 4,
        children: [
          entry(VotePosition.pour, 'Pour', colors.pour),
          entry(VotePosition.contre, 'Contre', colors.contre),
          entry(VotePosition.abstention, 'Abstention', colors.ink2),
        ],
      ),
    );
  }
}

/// Groupe de la page, à 28 points du précédent : rangées sur le fond entre
/// des filets, ou contenu à 12 points des filets et des bords ([padded]).
class _Group extends StatelessWidget {
  const _Group({required this.children, this.padded = false});

  final List<Widget> children;
  final bool padded;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: RuledRows(
      children: [
        for (final row in children)
          padded ? Padding(padding: const EdgeInsets.all(12), child: row) : row,
      ],
    ),
  );
}

/// Rangée d'un groupe : libellé et pictogramme à droite, 52 points de haut.
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.label,
    required this.glyph,
    required this.onTap,
    this.link = false,
  });

  final String label;
  final LineGlyph glyph;
  final VoidCallback onTap;

  /// Lien vers une page externe (pour les lecteurs d'écran).
  final bool link;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      link: link,
      button: !link,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: HemicycleText.label.copyWith(color: colors.ink),
                  ),
                ),
                const SizedBox(width: 12),
                LineIcon(glyph, size: 18, strokeWidth: 1.8, color: colors.ink2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
