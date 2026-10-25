import 'package:flutter/material.dart';

import 'about_page.dart';
import 'add_widget_page.dart';
import 'app_identity.dart';
import 'hemicycle/hemicycle_logo.dart';
import 'hemicycle/line_icon.dart';
import 'theme.dart';

// Boutons de l'en-tête de l'accueil vers les écrans de découverte.

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

/// Barre de l'accueil : logo et nom, boutons « Ajouter le widget » et « À
/// propos ».
class BrandBar extends StatelessWidget {
  const BrandBar({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 20, right: 10),
    child: Row(
      children: [
        HemicycleLogo.small(),
        SizedBox(width: 10),
        Expanded(child: Text(appName, style: HemicycleText.labelStrong)),
        AddWidgetAction(),
        AboutAction(),
      ],
    ),
  );
}
