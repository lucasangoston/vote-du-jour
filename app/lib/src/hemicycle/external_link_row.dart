import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'line_icon.dart';

/// Lien vers une page externe : rangée de 48 points sur la surface, flèche
/// sortante à droite (détail, À propos).
class ExternalLinkRow extends StatelessWidget {
  const ExternalLinkRow({super.key, required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      link: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.ink,
                      ),
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
      ),
    );
  }
}

/// Écran secondaire de la charte : bouton retour, grand titre, contenu sur
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
                style: HemicycleText.pageTitle.copyWith(
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
