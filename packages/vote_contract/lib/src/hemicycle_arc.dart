/// Vote d'un tronçon de l'arc dans l'ordre de l'hémicycle (#67).
enum ArcPosition {
  pour('pour'),
  abstention('abstention'),
  contre('contre');

  const ArcPosition(this.json);

  final String json;

  static ArcPosition? tryParse(Object? value) =>
      ArcPosition.values.where((p) => p.json == value).firstOrNull;
}

/// Tronçon de l'arc du vote dans l'ordre de l'hémicycle (#67) : [n] voix
/// exprimées dans le sens [position].
///
/// L'arc ([DecisionSummary.arc]) est une liste de tronçons ordonnée de gauche
/// à droite : les groupes politiques à leur place dans l'hémicycle, chacun
/// découpé selon les votes de ses membres (pour, abstention, contre). Deux
/// tronçons voisins de même sens sont fusionnés.
class HemicycleSegment {
  const HemicycleSegment(this.position, this.n);

  final ArcPosition position;

  /// Nombre de voix, strictement positif.
  final int n;

  /// Tronçons [segments] sans les tronçons vides, les voisins de même sens
  /// fusionnés.
  static List<HemicycleSegment> merge(Iterable<HemicycleSegment> segments) {
    final merged = <HemicycleSegment>[];
    for (final s in segments) {
      if (s.n <= 0) continue;
      if (merged.isNotEmpty && merged.last.position == s.position) {
        merged.last = HemicycleSegment(s.position, merged.last.n + s.n);
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  /// Lit un arc publié ; `null` s'il est absent, vide ou malformé. Un seul
  /// tronçon illisible (sens inconnu ajouté par un job plus récent, nombre
  /// manquant, nul ou négatif) rend tout l'arc illisible : ses proportions
  /// seraient fausses. Le lecteur dessine alors l'arc par sens.
  static List<HemicycleSegment>? tryParseList(Object? json) {
    if (json is! List || json.isEmpty) return null;
    final segments = <HemicycleSegment>[];
    for (final item in json) {
      if (item is! Map<String, Object?>) return null;
      final position = ArcPosition.tryParse(item['position']);
      final n = item['n'];
      if (position == null || n is! int || n <= 0) return null;
      segments.add(HemicycleSegment(position, n));
    }
    return segments;
  }

  Map<String, Object?> toJson() => {'position': position.json, 'n': n};

  @override
  bool operator ==(Object other) =>
      other is HemicycleSegment && other.position == position && other.n == n;

  @override
  int get hashCode => Object.hash(position, n);

  @override
  String toString() => 'HemicycleSegment(${position.json}, $n)';
}
