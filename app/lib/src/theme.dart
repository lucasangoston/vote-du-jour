import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Police des textes (titres en semi-gras, interlettrage serré).
const geist = 'Geist';

/// Police des chiffres (décomptes).
const geistMono = 'GeistMono';

/// Police des titres éditoriaux (#76), à empattements. Fichier variable :
/// la graisse passe par `fontVariations` (voir [HemicycleText.serif]).
const newsreader = 'Newsreader';

/// Couleurs de la charte « Hémicycle » (#29) : fond, surface, encres et filet
/// neutres ; seuls le pour (vert) et le contre (brique) portent une couleur,
/// jamais de couleur de parti ni de bleu-blanc-rouge.
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
  });

  static const light = HemicycleColors(
    background: Color(0xFFF3F4F5),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF15181C),
    ink2: Color(0xFF4F5761),
    body: Color(0xFF2E343B),
    rule: Color(0xFFE2E5E8),
    pour: Color(0xFF1D6B54),
    contre: Color(0xFFB4472B),
    abstention: Color(0xFFAEB4BB),
    pressed: Color(0xFFE8EAEC),
    raised: Color(0xFFE8EAEC),
  );

  static const dark = HemicycleColors(
    background: Color(0xFF0F1113),
    surface: Color(0xFF191C20),
    ink: Color(0xFFECEEF0),
    ink2: Color(0xFF9AA2AB),
    body: Color(0xFFC9CED3),
    rule: Color(0xFF2A2F35),
    pour: Color(0xFF4FB08F),
    contre: Color(0xFFE07A58),
    abstention: Color(0xFF4A5058),
    pressed: Color(0xFF1F2328),
    raised: Color(0xFF23272C),
  );

  /// Fond des écrans.
  final Color background;

  /// Cartes et boutons de lien.
  final Color surface;

  /// Encre principale (titres, texte).
  final Color ink;

  /// Encre secondaire (méta, légendes).
  final Color ink2;

  /// Texte courant des explications, entre [ink] et [ink2].
  final Color body;

  /// Filets de séparation.
  final Color rule;

  /// Pour, adopté.
  final Color pour;

  /// Contre, rejeté.
  final Color contre;

  /// Abstentions.
  final Color abstention;

  /// Fond d'un élément touché (ligne de liste, bouton icône).
  final Color pressed;

  /// Fond en creux d'un sélecteur segmenté (Auto / Jour / Nuit), sous le
  /// segment choisi qui prend [surface].
  final Color raised;

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
      contentTextStyle: TextStyle(fontFamily: geist, color: c.background),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: geist,
        fontSize: 13,
        color: c.background,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink2),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.surface : c.background,
        ),
        foregroundColor: WidgetStatePropertyAll(c.ink),
        side: WidgetStatePropertyAll(BorderSide(color: c.rule)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: geist,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(
          fontFamily: geist,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

/// Rayons d'angle de la charte, en points : à changer ici seulement.
abstract final class HemicycleRadii {
  /// Carte du vote du détail.
  static const card = 24.0;

  /// Vignette d'un groupe (« Qui a voté quoi »).
  static const tile = 14.0;
}

/// Styles de texte de la charte, d'après les maquettes (tailles en points
/// logiques, interlettrage converti des `em` de la maquette).
abstract final class HemicycleText {
  /// Grand titre d'écran (« Décisions »).
  static const largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.02,
    height: 1.15,
  );

  /// Titre d'une page annexe.
  static const pageTitle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.9,
    height: 1.15,
  );

  /// Titre d'une décision dans le détail.
  static const detailTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.65,
    height: 1.2,
  );

  /// Intertitre (« Ce que prévoit le texte »).
  static const heading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.18,
    height: 1.3,
  );

  /// Titre d'une ligne de la liste.
  static const rowTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.16,
    height: 1.3,
  );

  /// Chiffres en Geist Mono.
  static const mono = TextStyle(
    fontFamily: geistMono,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Chiffres alignés en Geist (`tabular-nums` des maquettes), à fusionner
  /// avec le style du texte qui les porte.
  static const figures = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Newsreader de [weight] et de [size] points. La police est variable : la
  /// graisse est donnée à l'axe `wght` (en plus de [TextStyle.fontWeight],
  /// que le moteur n'applique pas seul à un fichier variable) et la taille
  /// optique suit la taille, comme `font-optical-sizing: auto`.
  static TextStyle serif({
    required double size,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0,
    double? height,
  }) => TextStyle(
    fontFamily: newsreader,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [
      FontVariation.weight(weight.value.toDouble()),
      FontVariation.opticalSize(size.clamp(6, 72).toDouble()),
    ],
    letterSpacing: letterSpacing,
    height: height,
  );

  /// Titre en Newsreader (« Adopté » du résultat, titre d'un widget).
  static final serifTitle = serif(size: 28, letterSpacing: -0.28, height: 1.15);

  /// Résultat en grand sous l'hémicycle du détail (#74).
  static final serifVerdict = serif(size: 34, letterSpacing: -0.34, height: 1);

  /// Grand chiffre en Newsreader (jour d'un vote à venir), chiffres
  /// alignés sur la ligne de base.
  static final serifFigure = serif(
    size: 72,
    weight: FontWeight.w500,
    letterSpacing: -1.44,
    height: 1,
  ).copyWith(fontFeatures: const [FontFeature.liningFigures()]);

  /// Date du jour en tête de l'accueil (#79).
  static final serifDay = serif(size: 30, letterSpacing: -0.45, height: 1.08);

  /// Titre court d'une carte de l'accueil.
  static final serifCardTitle = serif(
    size: 26,
    letterSpacing: -0.26,
    height: 1.12,
  );

  /// Languette d'une carte de l'accueil (« Vote solennel », « 13 oct. »).
  static const tabLabel = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  /// Décompte d'une carte de l'accueil, après le symbole de chaque vote.
  static const tally = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Bouton principal (« Toutes les décisions »).
  static const primaryButton = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}
