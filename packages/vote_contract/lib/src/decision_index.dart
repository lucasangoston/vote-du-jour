import 'decision.dart';
import 'in_debate.dart';
import 'paths.dart';
import 'upcoming_item.dart';

/// Nombre maximal de décisions dans l'index.
const int maxIndexDecisions = 50;

/// Mention de la source exigée par la Licence Ouverte.
class SourceAttribution {
  const SourceAttribution({
    required this.name,
    required this.url,
    required this.license,
    required this.licenseUrl,
  });

  static const assembleeNationale = SourceAttribution(
    name: 'Assemblée nationale — open data',
    url: 'https://data.assemblee-nationale.fr',
    license: 'Licence Ouverte / Open Licence (Etalab)',
    licenseUrl: 'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
  );

  final String name;
  final String url;
  final String license;
  final String licenseUrl;

  static SourceAttribution fromJson(Object? json) {
    if (json is! Map<String, Object?>) return assembleeNationale;
    String read(String key, String fallback) =>
        json[key] is String ? json[key] as String : fallback;
    return SourceAttribution(
      name: read('name', assembleeNationale.name),
      url: read('url', assembleeNationale.url),
      license: read('license', assembleeNationale.license),
      licenseUrl: read('licenseUrl', assembleeNationale.licenseUrl),
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'license': license,
    'licenseUrl': licenseUrl,
  };
}

/// Le fichier `latest.json` : les dernières décisions, de la plus récente à la
/// plus ancienne.
class DecisionIndex {
  const DecisionIndex({
    required this.generatedAt,
    required this.decisions,
    this.source = SourceAttribution.assembleeNationale,
    this.upcoming,
    this.inDebate,
  });

  /// Instant de génération du fichier par le job.
  final DateTime generatedAt;

  final List<DecisionSummary> decisions;
  final SourceAttribution source;

  /// Ordre du jour des prochains jours (#52) : textes discutés et votes
  /// solennels, du plus proche au plus lointain. Champ optionnel : `null`
  /// dans les index publiés avant son ajout, ou tant que le job n'a jamais
  /// pu lire l'agenda ; une liste vide quand rien n'est inscrit.
  final List<UpcomingItem>? upcoming;

  /// Texte en débat (#55) : texte discuté lors de la séance en cours ou de
  /// la dernière séance des 7 derniers jours, et ses articles votés au
  /// scrutin public. Champ optionnel : `null` sans texte en débat, dans les
  /// index publiés avant son ajout, ou tant que le job n'a jamais pu lire
  /// l'agenda.
  final InDebate? inDebate;

  /// Le même index avec l'ordre du jour [upcoming].
  DecisionIndex withUpcoming(List<UpcomingItem>? upcoming) => DecisionIndex(
    generatedAt: generatedAt,
    decisions: decisions,
    source: source,
    upcoming: upcoming,
    inDebate: inDebate,
  );

  /// Le même index avec le texte en débat [inDebate].
  DecisionIndex withInDebate(InDebate? inDebate) => DecisionIndex(
    generatedAt: generatedAt,
    decisions: decisions,
    source: source,
    upcoming: upcoming,
    inDebate: inDebate,
  );

  /// Le même index avec les décisions [decisions] (ordre du jour et texte en
  /// débat gardés).
  DecisionIndex withDecisions(
    List<DecisionSummary> decisions, {
    DateTime? generatedAt,
  }) => DecisionIndex(
    generatedAt: generatedAt ?? this.generatedAt,
    decisions: decisions,
    source: source,
    upcoming: upcoming,
    inDebate: inDebate,
  );

  /// Lit un index publié.
  ///
  /// Lève [UnsupportedSchemaException] si le fichier n'est pas en version
  /// [schemaVersion], et [FormatException] s'il est malformé. Les décisions
  /// illisibles (valeur inconnue ajoutée par un job plus récent) sont ignorées,
  /// comme les points à venir illisibles ; un texte en débat malformé vaut
  /// absence.
  factory DecisionIndex.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Index : objet JSON attendu');
    }
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw UnsupportedSchemaException(version);
    }
    final generatedAt = DateTime.tryParse('${json['generatedAt']}');
    final decisions = json['decisions'];
    final upcoming = json['upcoming'];
    if (generatedAt == null || decisions is! List) {
      throw const FormatException('Index : generatedAt ou decisions invalide');
    }
    return DecisionIndex(
      generatedAt: generatedAt,
      source: SourceAttribution.fromJson(json['source']),
      decisions: [
        for (final d in decisions)
          if (d is Map<String, Object?>) ?DecisionSummary.tryFromJson(d),
      ],
      upcoming: upcoming is List
          ? [for (final u in upcoming) ?UpcomingItem.tryFromJson(u)]
          : null,
      inDebate: InDebate.tryFromJson(json['inDebate']),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'source': source.toJson(),
    'decisions': [for (final d in decisions) d.toJson()],
    'upcoming': ?upcoming?.map((u) => u.toJson()).toList(),
    'inDebate': ?inDebate?.toJson(),
  };
}

/// L'index publié utilise une version de schéma que ce code ne sait pas lire.
class UnsupportedSchemaException implements Exception {
  const UnsupportedSchemaException(this.found);

  final Object? found;

  @override
  String toString() =>
      'UnsupportedSchemaException: version $found, attendue $schemaVersion';
}
