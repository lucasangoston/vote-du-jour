import 'decision.dart';
import 'decision_arguments.dart';
import 'decision_index.dart';
import 'hemicycle_seat.dart';
import 'paths.dart';

/// Chemin du fichier de détail de la décision [id], relatif à l'URL publique :
/// `v1/decisions/<id>.json`.
String decisionDetailPath(String id) => 'v$schemaVersion/decisions/$id.json';

/// Position d'un groupe politique lors d'un scrutin : celle qui a recueilli le
/// plus de voix parmi ses membres (pour, contre ou abstention).
///
/// Elle est calculée à partir du décompte du groupe, et non lue dans le champ
/// `positionMajoritaire` de l'open data, qui vaut « pour » quand aucun membre
/// n'a voté et contredit le décompte dans environ 5 % des cas.
enum GroupPosition {
  pour('pour'),
  contre('contre'),
  abstention('abstention'),

  /// Égalité entre les positions les plus suivies.
  partage('partage'),

  /// Aucun membre du groupe n'a voté (ni pour, ni contre, ni abstention).
  nonVotant('nonVotant');

  const GroupPosition(this.json);

  final String json;

  static GroupPosition? tryParse(Object? value) =>
      GroupPosition.values.where((p) => p.json == value).firstOrNull;

  /// Position correspondant au décompte [count] d'un groupe.
  static GroupPosition fromCount(VoteCount count) {
    final best = [
      count.pour,
      count.contre,
      count.abstentions,
    ].reduce((a, b) => a > b ? a : b);
    if (best == 0) return nonVotant;
    final leaders = [
      if (count.pour == best) pour,
      if (count.contre == best) contre,
      if (count.abstentions == best) abstention,
    ];
    return leaders.length == 1 ? leaders.single : partage;
  }
}

/// Décompte des voix d'un scrutin ou d'un groupe.
class VoteCount {
  const VoteCount({
    required this.pour,
    required this.contre,
    required this.abstentions,
    required this.nonVotants,
  });

  final int pour;
  final int contre;
  final int abstentions;

  /// Députés présents qui n'ont pas pris part au vote (président de séance,
  /// membres du Gouvernement…).
  final int nonVotants;

  /// Votants : pour, contre et abstentions.
  int get votants => pour + contre + abstentions;

  /// Version légère publiée dans l'index ([DecisionSummary.count]).
  VoteTally get tally =>
      VoteTally(pour: pour, contre: contre, abstentions: abstentions);

  static VoteCount? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final pour = json['pour'];
    final contre = json['contre'];
    final abstentions = json['abstentions'];
    final nonVotants = json['nonVotants'];
    if (pour is! int ||
        contre is! int ||
        abstentions is! int ||
        nonVotants is! int) {
      return null;
    }
    return VoteCount(
      pour: pour,
      contre: contre,
      abstentions: abstentions,
      nonVotants: nonVotants,
    );
  }

  Map<String, Object?> toJson() => {
    'pour': pour,
    'contre': contre,
    'abstentions': abstentions,
    'nonVotants': nonVotants,
  };

  @override
  bool operator ==(Object other) =>
      other is VoteCount &&
      other.pour == pour &&
      other.contre == contre &&
      other.abstentions == abstentions &&
      other.nonVotants == nonVotants;

  @override
  int get hashCode => Object.hash(pour, contre, abstentions, nonVotants);

  @override
  String toString() =>
      'VoteCount(pour: $pour, contre: $contre, abstentions: $abstentions, '
      'nonVotants: $nonVotants)';
}

/// Vote d'un groupe politique.
class GroupVoteDetail {
  const GroupVoteDetail({
    required this.organeRef,
    required this.name,
    required this.position,
    required this.count,
    this.abbreviation,
    this.color,
  });

  /// Référence officielle du groupe (organe), par exemple `PO845401`.
  final String organeRef;

  /// Nom du groupe (« Rassemblement National »), ou « Groupe non identifié »
  /// si l'open data ne le donne pas.
  final String name;

  /// Sigle (« RN », « EcoS »), si connu.
  final String? abbreviation;

  /// Couleur officielle du groupe (`couleurAssociee` de l'archive AMO), au
  /// format `#RRGGBB` (#71). Absente des détails publiés avant son ajout ;
  /// une couleur malformée est ignorée.
  final String? color;

  final GroupPosition position;
  final VoteCount count;

  static GroupVoteDetail? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final organeRef = json['organeRef'];
    final name = json['name'];
    final position = GroupPosition.tryParse(json['position']);
    final count = VoteCount.tryFromJson(json['count']);
    if (organeRef is! String ||
        name is! String ||
        position == null ||
        count == null) {
      return null;
    }
    final abbreviation = json['abbreviation'];
    final color = json['color'];
    return GroupVoteDetail(
      organeRef: organeRef,
      name: name,
      abbreviation: abbreviation is String && abbreviation.trim().isNotEmpty
          ? abbreviation
          : null,
      color: color is String && _hexColor.hasMatch(color) ? color : null,
      position: position,
      count: count,
    );
  }

  static final _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}$');

  Map<String, Object?> toJson() => {
    'organeRef': organeRef,
    'name': name,
    'abbreviation': ?abbreviation,
    'color': ?color,
    'position': position.json,
    'count': count.toJson(),
  };
}

/// Le fichier de détail d'une décision (`v1/decisions/<id>.json`) : la
/// décision telle qu'elle figure dans l'index, plus le décompte et le vote
/// par groupe politique.
///
/// Le fichier ne porte pas d'horodatage : tant que la décision ne change pas,
/// son contenu reste identique octet pour octet, ce qui permet au job de ne
/// réécrire que les fichiers qui ont changé.
class DecisionDetail {
  const DecisionDetail({
    required this.decision,
    this.count,
    this.groups = const [],
    this.source = SourceAttribution.assembleeNationale,
    this.arguments,
    this.seats,
  });

  /// Champs de l'index (titre court, intitulé officiel, type, résultat, date,
  /// étape, liens).
  final DecisionSummary decision;

  /// Décompte du scrutin ; absent pour un texte adopté sans scrutin public
  /// (à main levée).
  final VoteCount? count;

  /// Vote de chaque groupe politique, dans l'ordre de l'open data (du plus
  /// grand au plus petit groupe) ; vide sans scrutin public.
  final List<GroupVoteDetail> groups;

  final SourceAttribution source;

  /// Arguments pour et contre tirés des explications de vote (ticket #35) ;
  /// absents sans explications de vote rattachées.
  final DecisionArguments? arguments;

  /// Place, groupe et vote de chaque député (#71), triés par place : la donnée
  /// de l'hémicycle « places réelles ». Les places sans vote nominatif sont
  /// [SeatVote.absent]. Absents pour une décision provisoire ou à main levée,
  /// quand le job n'a pas pu les vérifier, dans les détails publiés avant
  /// leur ajout ou s'ils sont malformés.
  final List<HemicycleSeat>? seats;

  /// Le même détail pour [decision] (par exemple, la décision résumée).
  DecisionDetail withDecision(DecisionSummary decision) => DecisionDetail(
    decision: decision,
    count: count,
    groups: groups,
    source: source,
    arguments: arguments,
    seats: seats,
  );

  /// Le même détail avec [seats] (`null` : sans sièges).
  DecisionDetail withSeats(List<HemicycleSeat>? seats) => DecisionDetail(
    decision: decision,
    count: count,
    groups: groups,
    source: source,
    arguments: arguments,
    seats: seats,
  );

  /// Le même détail avec [arguments] (`null` : sans arguments).
  DecisionDetail withArguments(DecisionArguments? arguments) => DecisionDetail(
    decision: decision,
    count: count,
    groups: groups,
    source: source,
    arguments: arguments,
    seats: seats,
  );

  /// Lit un fichier de détail publié.
  ///
  /// Lève [UnsupportedSchemaException] si le fichier n'est pas en version
  /// [schemaVersion], et [FormatException] s'il est malformé ou si la
  /// décision utilise une valeur inconnue. Un groupe illisible est ignoré ;
  /// des arguments ou des sièges malformés aussi (le détail reste lisible,
  /// sans eux).
  factory DecisionDetail.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Détail : objet JSON attendu');
    }
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw UnsupportedSchemaException(version);
    }
    final decisionJson = json['decision'];
    final decision = decisionJson is Map<String, Object?>
        ? DecisionSummary.tryFromJson(decisionJson)
        : null;
    if (decision == null) {
      throw const FormatException('Détail : decision invalide');
    }
    final groups = json['groups'];
    return DecisionDetail(
      decision: decision,
      source: SourceAttribution.fromJson(json['source']),
      count: VoteCount.tryFromJson(json['count']),
      groups: [
        if (groups is List)
          for (final g in groups) ?GroupVoteDetail.tryFromJson(g),
      ],
      arguments: DecisionArguments.tryFromJson(json['arguments']),
      seats: HemicycleSeat.tryParseList(json['seats']),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'source': source.toJson(),
    'decision': decision.toJson(summaryPoints: true),
    'count': ?count?.toJson(),
    'groups': [for (final g in groups) g.toJson()],
    'arguments': ?arguments?.toJson(),
    'seats': ?seats?.map((s) => s.toJson()).toList(),
  };
}
