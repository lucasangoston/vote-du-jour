import 'package:flutter/material.dart';

import 'about_page.dart';
import 'add_widget_page.dart';
import 'hemicycle/line_icon.dart';

// Boutons de l'en-tête de la liste vers les écrans de découverte.

/// Ouvre « Ajouter le widget ».
class AddWidgetAction extends StatelessWidget {
  const AddWidgetAction({super.key});

  @override
  Widget build(BuildContext context) => LineIconButton(
    tooltip: 'Ajouter le widget',
    glyph: LineGlyph.widgets,
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddWidgetPage())),
  );
}

/// Ouvre « À propos ».
class AboutAction extends StatelessWidget {
  const AboutAction({super.key});

  @override
  Widget build(BuildContext context) => LineIconButton(
    tooltip: 'À propos',
    glyph: LineGlyph.info,
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
  );
}
