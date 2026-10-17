import 'package:flutter/material.dart';

import 'about_page.dart';
import 'add_widget_page.dart';

// Boutons de l'AppBar de la liste vers les écrans de découverte.

/// Ouvre « Ajouter le widget ».
class AddWidgetAction extends StatelessWidget {
  const AddWidgetAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Ajouter le widget',
    icon: const Icon(Icons.widgets_outlined),
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddWidgetPage())),
  );
}

/// Ouvre « À propos et méthode ».
class AboutAction extends StatelessWidget {
  const AboutAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'À propos et méthode',
    icon: const Icon(Icons.info_outline),
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
  );
}
