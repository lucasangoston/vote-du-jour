import 'plain_summary.dart';

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

/// Manière dont l'Assemblée a voté.
enum VoteMode {
  /// Scrutin public : numéro de scrutin, décompte des voix et votes par
  /// groupe.
  scrutinPublic('scrutin_public'),

  /// Vote à main levée, repéré dans les dossiers législatifs : ni numéro de
  /// scrutin, ni décompte, ni vote par groupe. Seuls les textes adoptés sont
  /// publiés.
  mainLevee('main_levee');

  const VoteMode(this.json);

  final String json;

  static VoteMode? tryParse(Object? value) =>
      VoteMode.values.where((m) => m.json == value).firstOrNull;
}

/// Une décision telle qu'elle apparaît dans l'index (liste et widgets).
class DecisionSummary {
  const DecisionSummary({
    required this.id,
    this.numero,
    required this.type,
    required this.status,
    required this.result,
    required this.date,
    required this.officialTitle,
    required this.sourceUrl,
    this.shortTitle,
    this.stage,
    this.dossierUrl,
    this.voteMode = VoteMode.scrutinPublic,
    this.summary,
    this.count,
  }) : assert(
         numero != null || voteMode != VoteMode.scrutinPublic,
         'un scrutin public a un numéro',
       );

  /// Identifiant stable de la décision : celui du scrutin
  /// (`VTANR5L17V7946`) pour un scrutin public, celui de l'acte de décision
  /// du dossier législatif (`L17-VD234087DEC`) pour un vote à main levée.
  final String id;

  /// Numéro du scrutin dans la législature ; `null` pour un vote à main
  /// levée ([VoteMode.mainLevee]).
  final int? numero;

  /// Scrutin public ou main levée. Champ optionnel du JSON : absent des
  /// index publiés avant le ticket #8, il vaut alors
  /// [VoteMode.scrutinPublic].
  final VoteMode voteMode;

  final DecisionType type;

  /// [DecisionStatus.provisoire] pour une décision lue sur le site de
  /// l'Assemblée pendant la séance (#10), [DecisionStatus.confirmee] une fois
  /// dans le jeu de données officiel. Champ optionnel à la lecture : absent,
  /// il vaut [DecisionStatus.confirmee]. Le job l'écrit toujours, car les
  /// versions de l'app antérieures au ticket #10 l'exigent.
  final DecisionStatus status;

  /// Issue pour le texte ou l'objet du vote, à afficher dans le badge. Elle
  /// suit le sort du scrutin, sauf pour [DecisionType.rejetPrealable] (motion
  /// adoptée, donc texte rejeté).
  final VoteResult result;

  /// Jour du vote (l'open data ne donne pas l'heure), à minuit UTC.
  final DateTime date;

  /// Intitulé officiel du scrutin, tel que publié par l'Assemblée ; pour un
  /// vote à main levée, titre du texte adopté (ou, à défaut, du dossier).
  final String officialTitle;

  /// Page officielle du scrutin sur le site de l'Assemblée ; pour un vote à
  /// main levée, page du dossier législatif.
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

  /// Résumé en langage simple (ticket #9) : titre lisible et phrase
  /// d'explication dans l'index ; les points en plus dans le fichier de
  /// détail. Absent tant que la décision n'est pas résumée (texte pas encore
  /// en ligne, échec du modèle) et dans les index publiés avant son ajout.
  final PlainSummary? summary;

  /// Décompte du scrutin public (pour, contre, abstentions), pour dessiner l'arc du vote dans la liste et les widgets (#29).
  /// Absent pour un vote à main levée et dans les index publiés avant son
  /// ajout.
  final VoteTally? count;

  /// Titre à afficher : celui du résumé, sinon [shortTitle], sinon
  /// [officialTitle].
  String get displayTitle => summary?.title ?? shortTitle ?? officialTitle;

  /// Phrase d'explication du résumé, si la décision est résumée.
  String? get explanation => summary?.explanation;

  /// La même décision avec le résumé [summary] (ou sans résumé).
  DecisionSummary withSummary(PlainSummary? summary) => DecisionSummary(
    id: id,
    numero: numero,
    type: type,
    status: status,
    result: result,
    date: date,
    officialTitle: officialTitle,
    sourceUrl: sourceUrl,
    shortTitle: shortTitle,
    stage: stage,
    dossierUrl: dossierUrl,
    voteMode: voteMode,
    summary: summary,
    count: count,
  );

  /// La même décision avec le décompte [count] (ou sans décompte).
  DecisionSummary withCount(VoteTally? count) => DecisionSummary(
    id: id,
    numero: numero,
    type: type,
    status: status,
    result: result,
    date: date,
    officialTitle: officialTitle,
    sourceUrl: sourceUrl,
    shortTitle: shortTitle,
    stage: stage,
    dossierUrl: dossierUrl,
    voteMode: voteMode,
    summary: summary,
    count: count,
  );

  /// Lit une décision ; renvoie `null` si elle utilise une valeur d'énumération
  /// inconnue (ajoutée par une version plus récente du job) ou est malformée.
  ///
  /// `numero` n'est exigé que pour un scrutin public. Les lecteurs antérieurs
  /// au ticket #8 l'exigent toujours : ils ignorent donc les décisions à
  /// main levée, sans erreur.
  static DecisionSummary? tryFromJson(Map<String, Object?> json) {
    final voteMode = json['voteMode'] == null
        ? VoteMode.scrutinPublic
        : VoteMode.tryParse(json['voteMode']);
    final type = DecisionType.tryParse(json['type']);
    final status = json['status'] == null
        ? DecisionStatus.confirmee
        : DecisionStatus.tryParse(json['status']);
    final result = VoteResult.tryParse(json['result']);
    final id = json['id'];
    final numero = json['numero'];
    final date = DateTime.tryParse('${json['date']}T00:00:00Z');
    final title = json['officialTitle'];
    final sourceUrl = json['sourceUrl'];
    if (voteMode == null ||
        type == null ||
        status == null ||
        result == null ||
        id is! String ||
        (numero is! int?) ||
        (numero == null && voteMode == VoteMode.scrutinPublic) ||
        date == null ||
        title is! String ||
        sourceUrl is! String) {
      return null;
    }
    return DecisionSummary(
      id: id,
      numero: numero,
      voteMode: voteMode,
      type: type,
      status: status,
      result: result,
      date: date,
      officialTitle: title,
      sourceUrl: sourceUrl,
      shortTitle: _optionalString(json['shortTitle']),
      stage: _optionalString(json['stage']),
      dossierUrl: _optionalString(json['dossierUrl']),
      summary: PlainSummary.tryFromJson(json['summary']),
      count: VoteTally.tryFromJson(json['count']),
    );
  }

  /// [summaryPoints] : les points du résumé ne sont publiés que dans le
  /// fichier de détail (`true`), pas dans l'index.
  Map<String, Object?> toJson({bool summaryPoints = false}) => {
    'id': id,
    'numero': ?numero,
    'voteMode': voteMode.json,
    'type': type.json,
    'status': status.json,
    'result': result.json,
    'date': formatDate(date),
    'officialTitle': officialTitle,
    'sourceUrl': sourceUrl,
    'shortTitle': ?shortTitle,
    'stage': ?stage,
    'dossierUrl': ?dossierUrl,
    'summary': ?summary?.toJson(withPoints: summaryPoints),
    'count': ?count?.toJson(),
  };
}

/// Voix d'un scrutin public telles que les montre l'arc du vote : pour,
/// contre, abstentions (#29).
///
/// Version légère de `VoteCount` publiée dans l'index : les non-votants n'y
/// figurent pas, car le site de l'Assemblée ne les donne pas pendant la
/// séance et l'arc n'en a pas besoin.
class VoteTally {
  const VoteTally({
    required this.pour,
    required this.contre,
    required this.abstentions,
  });

  final int pour;
  final int contre;
  final int abstentions;

  /// Pour, contre et abstentions : la base de l'arc.
  int get total => pour + contre + abstentions;

  static VoteTally? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final pour = json['pour'];
    final contre = json['contre'];
    final abstentions = json['abstentions'];
    if (pour is! int || contre is! int || abstentions is! int) return null;
    if (pour < 0 || contre < 0 || abstentions < 0) return null;
    return VoteTally(pour: pour, contre: contre, abstentions: abstentions);
  }

  Map<String, Object?> toJson() => {
    'pour': pour,
    'contre': contre,
    'abstentions': abstentions,
  };

  @override
  bool operator ==(Object other) =>
      other is VoteTally &&
      other.pour == pour &&
      other.contre == contre &&
      other.abstentions == abstentions;

  @override
  int get hashCode => Object.hash(pour, contre, abstentions);

  @override
  String toString() =>
      'VoteTally(pour: $pour, contre: $contre, abstentions: $abstentions)';
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
