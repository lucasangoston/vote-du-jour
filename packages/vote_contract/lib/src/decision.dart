/// Nature d'une décision retenue parmi les scrutins.
enum DecisionType {
  /// Vote sur l'ensemble d'un projet ou d'une proposition de loi.
  ensembleTexte('ensemble'),

  /// Motion de censure (article 49 de la Constitution).
  motionDeCensure('motion_de_censure'),

  /// Déclaration du Gouvernement (article 50-1) ou déclaration de politique
  /// générale (article 49, alinéa 1).
  declarationGouvernement('declaration_gouvernement'),

  /// Motion de rejet préalable adoptée : le texte est rejeté
  /// ([VoteResult.rejete]).
  rejetPrealable('rejet_prealable'),

  /// Rejet de la première partie d'une loi de finances ou de financement de la
  /// sécurité sociale : tout le texte tombe ([VoteResult.rejete]).
  premierePartieBudget('premiere_partie_budget'),

  /// Proposition de résolution (article 34-1, commission d'enquête), sans
  /// portée normative.
  resolution('resolution'),

  /// Scrutin solennel dont l'intitulé n'est pas reconnu (garde-fou).
  autre('autre');

  const DecisionType(this.json);

  final String json;

  static DecisionType? tryParse(Object? value) =>
      DecisionType.values.where((t) => t.json == value).firstOrNull;
}

/// Résultat du vote à l'Assemblée.
enum VoteResult {
  adopte('adopte'),
  rejete('rejete');

  const VoteResult(this.json);

  final String json;

  static VoteResult? tryParse(Object? value) =>
      VoteResult.values.where((r) => r.json == value).firstOrNull;
}

/// Fiabilité de la décision publiée.
enum DecisionStatus {
  /// Lue sur le site de l'Assemblée, pas encore dans le jeu de données officiel.
  provisoire('provisoire'),

  /// Issue du jeu de données officiel de l'Assemblée.
  confirmee('confirmee');

  const DecisionStatus(this.json);

  final String json;

  static DecisionStatus? tryParse(Object? value) =>
      DecisionStatus.values.where((s) => s.json == value).firstOrNull;
}

/// Une décision telle qu'elle apparaît dans l'index (liste et widgets).
class DecisionSummary {
  const DecisionSummary({
    required this.id,
    required this.numero,
    required this.type,
    required this.status,
    required this.result,
    required this.date,
    required this.officialTitle,
    required this.sourceUrl,
    this.shortTitle,
    this.stage,
    this.dossierUrl,
  });

  /// Identifiant officiel du scrutin (par exemple `VTANR5L17V7946`).
  final String id;

  /// Numéro du scrutin dans la législature.
  final int numero;

  final DecisionType type;
  final DecisionStatus status;

  /// Issue pour le texte ou l'objet du vote, à afficher dans le badge. Elle
  /// suit le sort du scrutin, sauf pour [DecisionType.rejetPrealable] (motion
  /// adoptée, donc texte rejeté).
  final VoteResult result;

  /// Jour du vote (l'open data ne donne pas l'heure), à minuit UTC.
  final DateTime date;

  /// Intitulé officiel du scrutin, tel que publié par l'Assemblée.
  final String officialTitle;

  /// Page officielle du scrutin sur le site de l'Assemblée.
  final String sourceUrl;

  /// Titre court et lisible, à afficher à la place de [officialTitle] dans la
  /// liste et les widgets : titre du dossier législatif, ou libellé construit
  /// à partir de l'intitulé (motion de censure, déclaration du Gouvernement).
  ///
  /// Optionnel : absent des index publiés avant son ajout.
  final String? shortTitle;

  /// Étape de la procédure (« 1re lecture à l'AN », « Texte de compromis
  /// (CMP) »…) ou étiquette qui en tient lieu (« Résolution (sans valeur de
  /// loi) », « Motion de censure »…), prête à afficher. Ne dit jamais qu'une
  /// loi est votée : c'est l'étape du vote à l'Assemblée.
  ///
  /// Optionnel : absent des index publiés avant son ajout.
  final String? stage;

  /// Page officielle du dossier législatif, si la décision y est rattachée.
  final String? dossierUrl;

  /// Titre à afficher : [shortTitle], sinon [officialTitle].
  String get displayTitle => shortTitle ?? officialTitle;

  /// Lit une décision ; renvoie `null` si elle utilise une valeur d'énumération
  /// inconnue (ajoutée par une version plus récente du job) ou est malformée.
  static DecisionSummary? tryFromJson(Map<String, Object?> json) {
    final type = DecisionType.tryParse(json['type']);
    final status = DecisionStatus.tryParse(json['status']);
    final result = VoteResult.tryParse(json['result']);
    final id = json['id'];
    final numero = json['numero'];
    final date = DateTime.tryParse('${json['date']}T00:00:00Z');
    final title = json['officialTitle'];
    final sourceUrl = json['sourceUrl'];
    if (type == null ||
        status == null ||
        result == null ||
        id is! String ||
        numero is! int ||
        date == null ||
        title is! String ||
        sourceUrl is! String) {
      return null;
    }
    return DecisionSummary(
      id: id,
      numero: numero,
      type: type,
      status: status,
      result: result,
      date: date,
      officialTitle: title,
      sourceUrl: sourceUrl,
      shortTitle: _optionalString(json['shortTitle']),
      stage: _optionalString(json['stage']),
      dossierUrl: _optionalString(json['dossierUrl']),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'numero': numero,
    'type': type.json,
    'status': status.json,
    'result': result.json,
    'date': formatDate(date),
    'officialTitle': officialTitle,
    'sourceUrl': sourceUrl,
    'shortTitle': ?shortTitle,
    'stage': ?stage,
    'dossierUrl': ?dossierUrl,
  };
}

/// Champ optionnel : une valeur absente, vide ou d'un autre type est ignorée
/// plutôt que de rendre la décision illisible.
String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// Formate un jour au format `AAAA-MM-JJ`.
String formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
