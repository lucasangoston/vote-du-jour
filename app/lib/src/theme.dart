import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Police de la structure (rangées, dates, chiffres, boutons), chiffres
/// tabulaires pour les décomptes ([HemicycleText.figures]).
const geist = 'Geist';

/// Police du récit et de l'affichage (#76, DESIGN.md), à empattements, en
/// graisse 400. Fichier variable : la graisse passe par `fontVariations`
/// (voir [HemicycleText.serif]).
const newsreader = 'Newsreader';

/// Couleurs de la charte (DESIGN.md, système inspiré de Wired) : un duo noir
/// et blanc de magazine imprimé, fond, surface, encres et filet neutres ;
/// seules les données portent une couleur (le vote et le résultat, les
/// groupes), jamais de couleur de marque.
@immutable
class HemicycleColors extends ThemeExtension<HemicycleColors> {
  const HemicycleColors({
    required this.background,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.body,
    required this.rule,
    required this.pour,
    required this.contre,
    required this.abstention,
    required this.pressed,
    required this.raised,
    required this.plate,
    required this.mark,
    required this.onMark,
  });

  static const light = HemicycleColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F5),
    ink: Color(0xFF000000),
    ink2: Color(0xFF6B6B6B),
    body: Color(0xFF1A1A1A),
    rule: Color(0xFFE0E0E0),
    pour: Color(0xFF1D6B54),
    contre: Color(0xFFB4472B),
    abstention: Color(0xFFAEB4BB),
    pressed: Color(0xFFEBEBEB),
    raised: Color(0xFFEBEBEB),
    plate: Color(0xFFFFFFFF),
    mark: Color(0xFF4F5761),
    onMark: Color(0xFFFFFFFF),
  );

  static const dark = HemicycleColors(
    background: Color(0xFF000000),
    surface: Color(0xFF121212),
    ink: Color(0xFFFFFFFF),
    ink2: Color(0xFF9E9E9E),
    body: Color(0xFFE6E6E6),
    rule: Color(0xFF2A2A2A),
    pour: Color(0xFF4FB08F),
    contre: Color(0xFFE07A58),
    abstention: Color(0xFF4A5058),
    pressed: Color(0xFF1F1F1F),
    raised: Color(0xFF1F1F1F),
    plate: Color(0xFFFFFFFF),
    mark: Color(0xFF4A5058),
    onMark: Color(0xFFFFFFFF),
  );

  /// Fond des écrans (`ground` de DESIGN.md) : blanc le jour, noir la nuit.
  final Color background;

  /// Surface douce : cartes de l'accueil, carte du vote, tuiles, panneaux.
  final Color surface;

  /// Encre pleine : titres, texte, bouton principal, choix d'un sélecteur.
  final Color ink;

  /// Encre secondaire (méta, légendes), à 4,5:1 au moins sur [surface].
  final Color ink2;

  /// Texte du récit (explication, points, arguments), entre [ink] et [ink2].
  final Color body;

  /// Filets de 1 point entre les rangées.
  final Color rule;

  /// Pour, adopté (couleur des données, inchangée).
  final Color pour;

  /// Contre, rejeté (couleur des données, inchangée).
  final Color contre;

  /// Abstentions (couleur des données, inchangée).
  final Color abstention;

  /// Fond d'un élément touché (rangée, bouton icône).
  final Color pressed;

  /// Surface relevée : tuile de groupe choisie, bande d'un widget.
  final Color raised;

  /// Blanc constant : plaque sous un logo de groupe, même la nuit (les logos
  /// sont dessinés pour un fond blanc), pastille d'un interrupteur.
  final Color plate;

  /// Vignette à sigle d'un groupe sans logo, et son texte ([onMark]).
  final Color mark;

  /// Texte d'une vignette à sigle ([mark]).
  final Color onMark;

  @override
  HemicycleColors copyWith({
    Color? background,
    Color? surface,
    Color? ink,
    Color? ink2,
    Color? body,
    Color? rule,
    Color? pour,
    Color? contre,
    Color? abstention,
    Color? pressed,
    Color? raised,
    Color? plate,
    Color? mark,
    Color? onMark,
  }) => HemicycleColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    body: body ?? this.body,
    rule: rule ?? this.rule,
    pour: pour ?? this.pour,
    contre: contre ?? this.contre,
    abstention: abstention ?? this.abstention,
    pressed: pressed ?? this.pressed,
    raised: raised ?? this.raised,
    plate: plate ?? this.plate,
    mark: mark ?? this.mark,
    onMark: onMark ?? this.onMark,
  );

  @override
  HemicycleColors lerp(HemicycleColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return HemicycleColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      ink2: mix(ink2, other.ink2),
      body: mix(body, other.body),
      rule: mix(rule, other.rule),
      pour: mix(pour, other.pour),
      contre: mix(contre, other.contre),
      abstention: mix(abstention, other.abstention),
      pressed: mix(pressed, other.pressed),
      raised: mix(raised, other.raised),
      plate: mix(plate, other.plate),
      mark: mix(mark, other.mark),
      onMark: mix(onMark, other.onMark),
    );
  }
}

extension HemicycleTheme on BuildContext {
  /// Couleurs de la charte du thème courant (clair par défaut).
  HemicycleColors get colors =>
      Theme.of(this).extension<HemicycleColors>() ?? HemicycleColors.light;
}

/// Thème de l'app, en clair ou en sombre.
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? HemicycleColors.dark
      : HemicycleColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.ink,
    onPrimary: c.background,
    secondary: c.ink2,
    onSecondary: c.background,
    secondaryContainer: c.surface,
    onSecondaryContainer: c.ink,
    error: c.contre,
    onError: c.background,
    surface: c.background,
    onSurface: c.ink,
    onSurfaceVariant: c.ink2,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.rule,
    outline: c.ink2,
    outlineVariant: c.rule,
    inverseSurface: c.ink,
    onInverseSurface: c.background,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: geist,
    scaffoldBackgroundColor: c.background,
  );
  final overlay = brightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  // Angle droit partout : aucun arrondi, aucune ombre (DESIGN.md).
  const square = RoundedRectangleBorder(borderRadius: HemicycleRadii.none);
  return base.copyWith(
    extensions: [c],
    splashFactory: InkRipple.splashFactory,
    highlightColor: c.pressed,
    splashColor: c.pressed,
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: overlay,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: c.ink,
      displayColor: c.ink,
      fontFamily: geist,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: HemicycleText.bodySmall.copyWith(color: c.background),
      behavior: SnackBarBehavior.floating,
      shape: square,
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: HemicycleRadii.none,
      ),
      textStyle: HemicycleText.meta.copyWith(color: c.background),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink2),
    // Sélecteur segmenté : un rectangle au filet d'encre, le choix en encre
    // pleine.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(square),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : c.background,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.background : c.ink,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.ink)),
        textStyle: const WidgetStatePropertyAll(HemicycleText.control),
      ),
    ),
    // Bouton principal : rectangle à l'encre pleine, 48 points de haut.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink,
        foregroundColor: c.background,
        shape: square,
        elevation: 0,
        minimumSize: const Size(0, 48),
        textStyle: HemicycleText.button,
      ),
    ),
  );
}

/// Rayons d'angle de la charte : angle droit partout (cartes, rangées,
/// boutons, sélecteurs, tuiles). Seuls les points de pagination et les
/// symboles du vote sont ronds, et les cadres imposés par le système
/// (widgets, notifications) gardent sa forme.
abstract final class HemicycleRadii {
  /// Angle droit.
  static const none = BorderRadius.zero;
}

/// Styles de texte de la charte, d'après DESIGN.md (tailles en points
/// logiques, interlettrage converti des `em`). Newsreader 400 pour tout ce
/// qui se lit comme un titre et pour le récit ; Geist pour la structure.
abstract final class HemicycleText {
  /// Newsreader de [size] points, en graisse 400. La police est variable :
  /// la graisse est donnée à l'axe `wght` (en plus de [TextStyle.fontWeight],
  /// que le moteur n'applique pas seul à un fichier variable) et la taille
  /// optique suit la taille, comme `font-optical-sizing: auto`.
  static TextStyle serif({
    required double size,
    double letterSpacing = 0,
    double? height,
  }) => TextStyle(
    fontFamily: newsreader,
    fontSize: size,
    fontWeight: FontWeight.w400,
    fontVariations: [
      const FontVariation.weight(400),
      FontVariation.opticalSize(size.clamp(6, 72).toDouble()),
    ],
    letterSpacing: letterSpacing,
    height: height,
  );

  /// `display-xl` : grand chiffre (jour d'un vote à venir), chiffres alignés
  /// sur la ligne de base.
  static final displayXl = serif(
    size: 72,
    letterSpacing: -1.44,
    height: 1,
  ).copyWith(fontFeatures: const [FontFeature.liningFigures()]);

  /// `display-lg` : titre d'écran (« Décisions », date de l'accueil),
  /// « Adopté » du détail.
  static final displayLg = serif(size: 34, letterSpacing: -0.68, height: 1.08);

  /// `display-md` : titre de la décision.
  static final displayMd = serif(size: 32, letterSpacing: -0.32, height: 1.1);

  /// `display-sm` : intertitres, titre d'une carte, résultat d'une carte.
  static final displaySm = serif(size: 26, height: 1.12);

  /// `body-serif` : récit (explication, points, arguments).
  static final bodySerif = serif(size: 18, height: 1.5);

  /// `body-strong` : titre d'une rangée de liste.
  static const bodyStrong = TextStyle(
    fontFamily: geist,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// `body-sm` : texte courant en Geist (messages, étapes).
  static const bodySmall = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Libellé d'une rangée de réglage ou de lien.
  static const label = TextStyle(
    fontFamily: geist,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Libellé appuyé : nom de l'app, camp d'une rangée de groupes.
  static const labelStrong = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Texte d'un sélecteur (filtres, apparence).
  static const control = TextStyle(
    fontFamily: geist,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  /// `meta` : date, intitulé, source.
  static const meta = TextStyle(
    fontFamily: geist,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Méta appuyée : jour d'un groupe de la liste, mot du résultat d'une
  /// rangée, languette d'une carte.
  static const metaStrong = TextStyle(
    fontFamily: geist,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// Légende sous le logo d'une tuile de groupe.
  static const caption = TextStyle(
    fontFamily: geist,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// Sigle d'une vignette sans logo (taille donnée par la vignette).
  static const mark = TextStyle(fontFamily: geist, fontWeight: FontWeight.w700);

  /// Chiffres alignés en Geist (`tabular-nums`), à fusionner avec le style
  /// du texte qui les porte.
  static const figures = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// `figure` : chiffres d'un décompte (503 · 0 · 67), Geist à chiffres
  /// tabulaires.
  static const figure = TextStyle(
    fontFamily: geist,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Décompte d'une carte de l'accueil, après le symbole de chaque vote.
  static const tally = TextStyle(
    fontFamily: geist,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// `button` : bouton principal (« Toutes les décisions »).
  static const button = TextStyle(
    fontFamily: geist,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.32,
  );
}
