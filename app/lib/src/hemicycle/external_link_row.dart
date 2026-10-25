import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'line_icon.dart';

/// Lien vers une page externe : rangée de 48 points sur le fond, flèche
/// sortante à droite (détail, en débat). Les filets viennent de [RuledRows].
class ExternalLinkRow extends StatelessWidget {
  const ExternalLinkRow({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: HemicycleText.label.copyWith(color: colors.ink),
                  ),
                ),
                const SizedBox(width: 12),
                LineIcon(
                  LineGlyph.external,
                  size: 18,
                  strokeWidth: 1.8,
                  color: colors.ink2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rangées sur le fond, séparées par des filets de 1 point : un filet
/// au-dessus de la première et sous chacune (DESIGN.md, `list-row`), sans
/// panneau ni arrondi.
class RuledRows extends StatelessWidget {
  const RuledRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => children.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            for (final row in children) ...[row, const Divider()],
          ],
        );
}

/// Écran secondaire de la charte : bouton retour, titre d'écran, contenu sur
/// le fond, marges de 20 points (À propos, Ajouter le widget).
class HemicyclePage extends StatelessWidget {
  const HemicyclePage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            padding.top,
            20,
            40 + padding.bottom,
          ),
          children: [
            const HemicycleBackButton(),
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                title,
                style: HemicycleText.displayLg.copyWith(
                  color: context.colors.ink,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
