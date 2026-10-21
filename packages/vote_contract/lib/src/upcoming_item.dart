/// Nature d'un point à venir de l'ordre du jour de l'Assemblée (#52).
enum UpcomingKind {
  /// Discussion d'un texte en séance publique (ou suite de sa discussion,
  /// [UpcomingItem.inProgress]).
  discussion('discussion'),

  /// Vote solennel (ou vote par scrutin public) inscrit à l'ordre du jour :
  /// le vote sur l'ensemble d'un texte, une motion de censure…
  voteSolennel('vote_solennel');

  const UpcomingKind(this.json);

  final String json;

  static UpcomingKind? tryParse(Object? value) =>
      UpcomingKind.values.where((k) => k.json == value).firstOrNull;
}

/// Un point à venir de l'ordre du jour officiel de l'Assemblée (bloc
/// `upcoming` de l'index) : un texte discuté ou un vote solennel dans les
/// prochains jours.
class UpcomingItem {
  const UpcomingItem({
    required this.id,
    required this.kind,
    required this.startsAt,
    required this.seanceRef,
    required this.label,
    required this.shortTitle,
    this.inProgress = false,
    this.dossierRef,
    this.dossierUrl,
  });

  /// Identifiant du point de l'ordre du jour
  /// (`RUANR5L17S2027IDS30964PT53289`), stable d'une publication à l'autre.
  final String id;

  final UpcomingKind kind;

  /// Début de la séance où le point est inscrit (instant UTC ; l'app
  /// l'affiche en heure de Paris). L'ordre du jour ne donne pas l'heure du
  /// point lui-même : un vote solennel a lieu après les questions au
  /// Gouvernement, vers 16 h.
  final DateTime startsAt;

  /// Identifiant de la séance (`RUANR5L17S2027IDS30964`), celui que cite le
  /// scrutin (`seanceRef`) une fois le vote passé.
  final String seanceRef;

  /// Libellé du point à l'ordre du jour, tel que publié (« Vote solennel sur
  /// le projet de loi de financement de la sécurité sociale pour 2027 »).
  final String label;

  /// Titre court et lisible, à afficher à la place de [label] : titre déjà
  /// publié pour une décision du même dossier, sinon titre du dossier, sinon
  /// libellé nettoyé.
  final String shortTitle;

  /// Discussion commencée avant la période couverte : seule sa suite est
  /// inscrite (« Suite de la discussion »). Optionnel, absent vaut `false`.
  final bool inProgress;

  /// Dossier législatif du texte (`DLR5L17N54951`), si l'ordre du jour le
  /// donne ou s'il a pu être retrouvé.
  final String? dossierRef;

  /// Page officielle du dossier législatif.
  final String? dossierUrl;

  /// Lit un point ; `null` s'il est malformé ou d'une nature inconnue
  /// (ajoutée par une version plus récente du job).
  static UpcomingItem? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final kind = UpcomingKind.tryParse(json['kind']);
    final startsAt = json['startsAt'] is String
        ? DateTime.tryParse(json['startsAt'] as String)
        : null;
    final seanceRef = json['seanceRef'];
    final label = json['label'];
    final shortTitle = json['shortTitle'];
    if (id is! String ||
        kind == null ||
        startsAt == null ||
        seanceRef is! String ||
        label is! String ||
        shortTitle is! String ||
        shortTitle.trim().isEmpty) {
      return null;
    }
    String? optional(Object? v) =>
        v is String && v.trim().isNotEmpty ? v : null;
    return UpcomingItem(
      id: id,
      kind: kind,
      startsAt: startsAt.toUtc(),
      seanceRef: seanceRef,
      label: label,
      shortTitle: shortTitle,
      inProgress: json['inProgress'] == true,
      dossierRef: optional(json['dossierRef']),
      dossierUrl: optional(json['dossierUrl']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.json,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'seanceRef': seanceRef,
    'label': label,
    'shortTitle': shortTitle,
    if (inProgress) 'inProgress': true,
    'dossierRef': ?dossierRef,
    'dossierUrl': ?dossierUrl,
  };

  @override
  String toString() =>
      'UpcomingItem(${kind.json} ${startsAt.toIso8601String()} $shortTitle)';
}
