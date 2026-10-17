import 'package:flutter/material.dart';

/// Palette neutre : nuances de gris, sans couleurs de partis ni
/// bleu-blanc-rouge. Seuls les badges adopté / rejeté portent une couleur.
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6B6B6B),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  return ThemeData(colorScheme: scheme, useMaterial3: true);
}

/// Couleurs des badges de résultat (vert / brique, lisibles en clair et en
/// sombre).
class ResultColors {
  static const adopted = Color(0xFF2E7D32);
  static const rejected = Color(0xFFB23B1E);
}
