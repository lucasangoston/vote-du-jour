/// Arguments pour et contre d'une décision (ticket #35), tirés des
/// explications de vote des groupes dans le compte rendu de la séance et
/// résumés automatiquement par un modèle de langage, sans relecture humaine.
///
/// Absents pour un vote sans explications de vote (main levée, petits
/// textes, conventions), pour une décision pas encore rattachée à son
/// compte rendu et dans les fichiers plus anciens.
class DecisionArguments {
  const DecisionArguments({
    required this.source,
    required this.promptVersion,
    this.pour = const [],
    this.contre = const [],
    this.abstention = const [],
  });

  /// Arguments des groupes qui ont voté pour.
  final List<GroupArgument> pour;

  /// Arguments des groupes qui ont voté contre.
  final List<GroupArgument> contre;

  /// Arguments des groupes qui se sont abstenus.
  final List<GroupArgument> abstention;

  /// Compte rendu dont les arguments sont tirés.
  final ArgumentsSource source;

  /// Version de la consigne donnée au modèle (fichier versionné dans le
  /// dépôt, `backend/lib/src/arguments/arguments_prompt.dart`).
  final int promptVersion;

  /// Aucun argument dans aucun camp.
  bool get isEmpty => pour.isEmpty && contre.isEmpty && abstention.isEmpty;

  /// Lit les arguments ; `null` s'ils sont absents ou malformés (source ou
  /// version absente, aucun argument lisible) : la décision reste lisible,
  /// sans la section. Un argument illisible est ignoré.
  static DecisionArguments? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final source = ArgumentsSource.tryFromJson(json['source']);
    final promptVersion = json['promptVersion'];
    if (source == null || promptVersion is! int) return null;
    List<GroupArgument> side(String key) => [
      if (json[key] case final List<Object?> items)
        for (final item in items) ?GroupArgument.tryFromJson(item),
    ];
    final arguments = DecisionArguments(
      source: source,
      promptVersion: promptVersion,
      pour: side('pour'),
      contre: side('contre'),
      abstention: side('abstention'),
    );
    return arguments.isEmpty ? null : arguments;
  }

  Map<String, Object?> toJson() => {
    'pour': [for (final a in pour) a.toJson()],
    'contre': [for (final a in contre) a.toJson()],
    'abstention': [for (final a in abstention) a.toJson()],
    'source': source.toJson(),
    'promptVersion': promptVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is DecisionArguments &&
      other.source == source &&
      other.promptVersion == promptVersion &&
      _sameList(other.pour, pour) &&
      _sameList(other.contre, contre) &&
      _sameList(other.abstention, abstention);

  @override
  int get hashCode => Object.hash(
    source,
    promptVersion,
    Object.hashAll(pour),
    Object.hashAll(contre),
    Object.hashAll(abstention),
  );

  @override
  String toString() =>
      'DecisionArguments(pour: $pour, contre: $contre, '
      'abstention: $abstention, source: $source, '
      'promptVersion: $promptVersion)';
}

/// Un argument, attribué au groupe politique qui l'a avancé.
class GroupArgument {
  const GroupArgument({
    required this.group,
    required this.text,
    this.organeRef,
  });

  /// Sigle du groupe (« SOC », « LFI-NFP »), comme `abbreviation` dans le
  /// vote par groupe du même fichier.
  final String group;

  /// Référence officielle du groupe (`PO845419`), si connue.
  final String? organeRef;

  /// L'argument, en une phrase courte.
  final String text;

  static GroupArgument? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final group = json['group'];
    final text = json['text'];
    if (group is! String ||
        group.trim().isEmpty ||
        text is! String ||
        text.trim().isEmpty) {
      return null;
    }
    final organeRef = json['organeRef'];
    return GroupArgument(
      group: group,
      text: text,
      organeRef: organeRef is String && organeRef.isNotEmpty ? organeRef : null,
    );
  }

  Map<String, Object?> toJson() => {
    'group': group,
    'organeRef': ?organeRef,
    'text': text,
  };

  @override
  bool operator ==(Object other) =>
      other is GroupArgument &&
      other.group == group &&
      other.organeRef == organeRef &&
      other.text == text;

  @override
  int get hashCode => Object.hash(group, organeRef, text);

  @override
  String toString() => 'GroupArgument($group, $text)';
}

/// Compte rendu de séance d'où viennent les arguments.
class ArgumentsSource {
  const ArgumentsSource({required this.date, required this.url});

  /// Jour de la séance (minuit UTC).
  final DateTime date;

  /// Page du compte rendu sur le site de l'Assemblée.
  final String url;

  static ArgumentsSource? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final date = DateTime.tryParse('${json['date']}T00:00:00Z');
    final url = json['url'];
    if (date == null || url is! String || url.isEmpty) return null;
    return ArgumentsSource(date: date, url: url);
  }

  Map<String, Object?> toJson() => {'date': _day(date), 'url': url};

  @override
  bool operator ==(Object other) =>
      other is ArgumentsSource && other.date == date && other.url == url;

  @override
  int get hashCode => Object.hash(date, url);

  @override
  String toString() => 'ArgumentsSource(${_day(date)}, $url)';
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
