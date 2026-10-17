import 'dart:convert';

import 'package:archive/archive.dart';

import 'decision_selector.dart' show normalizeTitle;
import 'dump_reader.dart' show DumpFormatException;

/// Archive des dossiers législatifs de la 17e législature (Licence Ouverte),
/// régénérée une fois par jour.
const dossiersDumpUrl =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/loi/dossiers_legislatifs/Dossiers_Legislatifs.json.zip';

/// Lecture à l'Assemblée au cours de laquelle un texte est voté.
enum Lecture {
  premiere("1re lecture à l'AN"),
  deuxieme("2e lecture à l'AN"),
  troisieme("3e lecture à l'AN"),
  nouvelle("Nouvelle lecture à l'AN"),
  definitive("Lecture définitive à l'AN"),
  commissionMixteParitaire('Texte de compromis (CMP)'),
  unique("Lecture unique à l'AN");

  const Lecture(this.label);

  /// Libellé affiché. Aucune lecture ne vaut « loi votée » : la procédure
  /// continue au Sénat ou au Conseil constitutionnel, puis à la promulgation.
  final String label;

  /// Lecture correspondant au code d'un acte de premier niveau d'un dossier
  /// (`AN1`, `AN2`, `ANNLEC`, `ANLDEF`, `CMP`, `ANLUNI`), ou `null` pour les
  /// autres (Sénat, `AN20` contrôle, `AN21` engagement de responsabilité…).
  static Lecture? fromActeCode(String code) => switch (code) {
    'AN1' => premiere,
    'AN2' => deuxieme,
    'AN3' => troisieme,
    'ANNLEC' => nouvelle,
    'ANLDEF' => definitive,
    'CMP' => commissionMixteParitaire,
    'ANLUNI' => unique,
    _ => null,
  };

  /// Lecture indiquée en fin d'intitulé de scrutin (« … (première lecture). »,
  /// « … (texte de la commission mixte paritaire). »), ou `null`.
  static Lecture? fromScrutinTitle(String titre) {
    final match = _trailingParenthesis.firstMatch(normalizeTitle(titre));
    return switch (match?.group(1)) {
      'première lecture' => premiere,
      'deuxième lecture' => deuxieme,
      'troisième lecture' => troisieme,
      'nouvelle lecture' => nouvelle,
      'lecture définitive' => definitive,
      'texte de la commission mixte paritaire' => commissionMixteParitaire,
      'lecture unique' => unique,
      _ => null,
    };
  }
}

final _trailingParenthesis = RegExp(r'\(([^()]*)\)\s*\.?\s*$');

/// Un dossier législatif de l'Assemblée.
class Dossier {
  const Dossier({required this.uid, required this.title});

  /// Identifiant officiel, par exemple `DLR5L17N50169`.
  final String uid;

  /// Titre du dossier (`titreDossier.titre`), par exemple « Proposition de loi
  /// visant à sortir la France du piège du narcotrafic ».
  final String title;

  /// Page officielle du dossier sur le site de l'Assemblée.
  String get url => 'https://www.assemblee-nationale.fr/dyn/17/dossiers/$uid';
}

/// Rattachement d'un scrutin à un dossier.
class DossierLink {
  const DossierLink({
    required this.dossier,
    required this.lecture,
    required this.isText,
  });

  final Dossier dossier;

  /// Lecture au cours de laquelle le scrutin a eu lieu, si le dossier la
  /// donne.
  final Lecture? lecture;

  /// Le dossier porte un texte (projet, proposition de loi ou de
  /// résolution), et non un engagement de responsabilité du Gouvernement
  /// (`AN21`) ou une mission de contrôle (`AN20`).
  final bool isText;
}

/// Index des dossiers législatifs : associe un scrutin à son dossier, pour en
/// tirer le titre court et l'étape de la procédure.
///
/// Le rattachement suit, dans l'ordre :
/// 1. la référence du scrutin dans les actes du dossier (`voteRefs`) ;
/// 2. la référence de dossier portée par le scrutin (`dossierRef`) ;
/// 3. l'intitulé du texte voté, comparé au titre du dossier et aux titres des
///    documents du dossier, retenu seulement si le dossier contient une
///    décision de l'Assemblée le jour du scrutin (sinon un texte homonyme
///    d'une autre année serait pris pour le bon).
class DossierIndex {
  DossierIndex._({
    required Map<String, String> titles,
    required Map<String, List<(String, String)>> votes,
    required Map<String, List<(String, String)>> decisions,
    required Map<String, Set<String>> titleKeys,
    required Set<String> nonTexts,
  }) : _titles = titles,
       _votes = votes,
       _decisions = decisions,
       _titleKeys = titleKeys,
       _nonTexts = nonTexts;

  /// Titre de chaque dossier, par identifiant.
  final Map<String, String> _titles;

  /// Pour chaque scrutin cité par un acte : (dossier, code de l'acte de
  /// premier niveau).
  final Map<String, List<(String, String)>> _votes;

  /// Pour chaque dossier : (code de l'acte de premier niveau, jour) des
  /// décisions de l'Assemblée en séance.
  final Map<String, List<(String, String)>> _decisions;

  /// Clé d'intitulé normalisée → dossiers portant cet intitulé.
  final Map<String, Set<String>> _titleKeys;

  /// Dossiers qui ne portent pas de texte (engagement de responsabilité,
  /// contrôle).
  final Set<String> _nonTexts;

  /// Nombre de dossiers indexés.
  int get length => _titles.length;

  Dossier? dossier(String uid) => switch (_titles[uid]) {
    final title? => Dossier(uid: uid, title: title),
    null => null,
  };

  /// Lit l'archive `Dossiers_Legislatifs.json.zip` (dossiers dans
  /// `json/dossierParlementaire/`, documents dans `json/document/`).
  ///
  /// Lève [DumpFormatException] si un dossier n'a pas le format attendu. Les
  /// documents ne servent qu'au rattachement par intitulé : un document
  /// illisible est ignoré.
  factory DossierIndex.fromArchive(List<int> zipBytes) {
    final builder = _Builder();
    for (final file in ZipDecoder().decodeBytes(zipBytes)) {
      final name = file.name.toLowerCase();
      if (!file.isFile || !name.endsWith('.json')) continue;
      if (name.contains('dossierparlementaire/')) {
        builder.addDossier(utf8.decode(file.content), source: file.name);
      } else if (name.contains('document/')) {
        builder.addDocument(utf8.decode(file.content));
      }
    }
    return builder.build();
  }

  /// Relit un index enregistré par [toJson] (cache entre deux exécutions du
  /// job). Lève [FormatException] s'il est illisible.
  factory DossierIndex.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != _cacheVersion) {
      throw const FormatException('Index des dossiers : version inattendue');
    }
    Map<String, Object?> map(Object? v) => v is Map<String, Object?>
        ? v
        : throw const FormatException('Index des dossiers : objet attendu');
    List<(String, String)> pairs(Object? v) => [
      for (final p in v as List) ((p as List)[0] as String, p[1] as String),
    ];
    try {
      return DossierIndex._(
        titles: map(json['titles']).cast<String, String>(),
        votes: {
          for (final e in map(json['votes']).entries) e.key: pairs(e.value),
        },
        decisions: {
          for (final e in map(json['decisions']).entries) e.key: pairs(e.value),
        },
        titleKeys: {
          for (final e in map(json['titleKeys']).entries)
            e.key: {...(e.value as List).cast<String>()},
        },
        nonTexts: {...(json['nonTexts'] as List).cast<String>()},
      );
    } on TypeError {
      throw const FormatException('Index des dossiers : format inattendu');
    }
  }

  static const _cacheVersion = 1;

  Map<String, Object?> toJson() {
    List<List<String>> pairs(List<(String, String)> l) => [
      for (final (a, b) in l) [a, b],
    ];
    return {
      'version': _cacheVersion,
      'titles': _titles,
      'votes': {for (final e in _votes.entries) e.key: pairs(e.value)},
      'decisions': {for (final e in _decisions.entries) e.key: pairs(e.value)},
      'titleKeys': {
        for (final e in _titleKeys.entries) e.key: e.value.toList()..sort(),
      },
      'nonTexts': _nonTexts.toList()..sort(),
    };
  }

  /// Rattache un scrutin à son dossier, ou renvoie `null`.
  ///
  /// [scrutinUid] : `VTANR5L17V…` ; [date] : jour du scrutin ; [titre] :
  /// intitulé officiel ; [dossierRef] : référence portée par le scrutin.
  DossierLink? link({
    required String scrutinUid,
    required DateTime date,
    required String titre,
    String? dossierRef,
  }) {
    final day = _day(date);

    // 1. Le scrutin est cité par un acte. Une motion de censure après 49.3
    // est citée par le dossier de l'engagement de responsabilité (AN21) et
    // par celui du texte : on préfère le texte.
    final cited = _votes[scrutinUid] ?? const [];
    if (cited.isNotEmpty) {
      final (uid, code) = cited.firstWhere(
        (c) => _isText(c.$2),
        orElse: () => cited.first,
      );
      if (dossier(uid) case final d?) {
        return DossierLink(
          dossier: d,
          lecture: Lecture.fromActeCode(code),
          isText: _isText(code),
        );
      }
    }

    // 2. Référence portée par le scrutin.
    if (dossierRef != null) {
      if (dossier(dossierRef) case final d?) {
        return DossierLink(
          dossier: d,
          lecture:
              _lectureOn(dossierRef, day) ?? Lecture.fromScrutinTitle(titre),
          isText: !_nonTexts.contains(dossierRef),
        );
      }
    }

    // 3. Intitulé du texte voté, confirmé par une décision le même jour.
    final object = votedTextKey(titre);
    if (object == null) return null;
    final candidates = [
      for (final uid in _titleKeys[object] ?? const <String>{})
        if (_decisions[uid]?.any((d) => d.$2 == day) ?? false) uid,
    ];
    if (candidates.length != 1) return null;
    final uid = candidates.single;
    return DossierLink(
      dossier: dossier(uid)!,
      lecture: _lectureOn(uid, day) ?? Lecture.fromScrutinTitle(titre),
      isText: true,
    );
  }

  /// Lecture de la décision prise par l'Assemblée le jour [day] dans le
  /// dossier, si elle est unique.
  Lecture? _lectureOn(String uid, String day) {
    final lectures = {
      for (final (code, d) in _decisions[uid] ?? const <(String, String)>[])
        if (d == day) Lecture.fromActeCode(code),
    };
    return lectures.length == 1 ? lectures.single : null;
  }

  static bool _isText(String code) => code != 'AN20' && code != 'AN21';
}

/// Clé de comparaison de l'intitulé du texte voté : à partir de « proposition
/// de loi… », « projet de loi… » ou « proposition de résolution… », sans la
/// parenthèse finale, la ponctuation ni la casse. `null` si l'intitulé ne
/// nomme pas de texte.
String? votedTextKey(String titre) {
  final match = _votedText.firstMatch(normalizeTitle(titre));
  return match == null ? null : _titleKey(match.group(0)!);
}

final _votedText = RegExp(
  r'(?:proposition de (?:loi|résolution)|projet de loi).*$',
);

String _titleKey(String title) => normalizeTitle(title)
    .replaceAll('œ', 'oe')
    .replaceFirst(_trailingParenthesis, '')
    .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
    .trim();

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _Builder {
  final titles = <String, String>{};
  final votes = <String, List<(String, String)>>{};
  final decisions = <String, List<(String, String)>>{};
  final titleKeys = <String, Set<String>>{};
  final topCodes = <String, Set<String>>{};

  void _addTitleKey(String title, String uid) {
    final key = _titleKey(title);
    if (key.isNotEmpty) titleKeys.putIfAbsent(key, () => {}).add(uid);
  }

  void addDossier(String json, {required String source}) {
    Never fail(String what) =>
        throw DumpFormatException(source, '$what inattendu');
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw DumpFormatException(source, 'JSON invalide : ${e.message}');
    }
    final d = decoded is Map<String, Object?>
        ? decoded['dossierParlementaire']
        : null;
    if (d is! Map<String, Object?>) fail('dossierParlementaire');
    final uid = d['uid'];
    if (uid is! String || uid.isEmpty) fail('uid');
    final titreDossier = d['titreDossier'];
    final title = titreDossier is Map<String, Object?>
        ? titreDossier['titre']
        : null;
    if (title is! String || title.trim().isEmpty) fail('titreDossier.titre');

    titles[uid] = title.trim();
    _addTitleKey(title, uid);
    for (final top in _list(_actes(d))) {
      if (top is! Map<String, Object?>) fail('acteLegislatif');
      final code = top['codeActe'];
      if (code is! String) fail('acteLegislatif.codeActe');
      topCodes.putIfAbsent(uid, () => {}).add(code);
      _walk(top, uid, code);
    }
  }

  /// Parcourt un acte et ses sous-actes : scrutins cités, décisions en
  /// séance.
  void _walk(Map<String, Object?> acte, String uid, String top) {
    for (final ref in _list(_map(acte['voteRefs'])?['voteRef'])) {
      if (ref is String) votes.putIfAbsent(ref, () => []).add((uid, top));
    }
    final code = acte['codeActe'];
    final date = acte['dateActe'];
    if (code is String &&
        _isAssemblyDecision(code) &&
        date is String &&
        date.length >= 10) {
      // `dateActe` est en heure de Paris : les dix premiers caractères
      // donnent le jour du scrutin.
      decisions.putIfAbsent(uid, () => []).add((top, date.substring(0, 10)));
    }
    for (final child in _list(_actes(acte))) {
      if (child is Map<String, Object?>) _walk(child, uid, top);
    }
  }

  /// Décision en séance à l'Assemblée (`AN1-DEBATS-DEC`,
  /// `CMP-DEBATS-AN-DEC`…), pas au Sénat.
  static bool _isAssemblyDecision(String code) =>
      !code.startsWith('SN') &&
      (code.endsWith('-DEBATS-DEC') || code.endsWith('-DEBATS-AN-DEC'));

  void addDocument(String json) {
    try {
      final doc = (jsonDecode(json) as Map<String, Object?>)['document'];
      if (doc is! Map<String, Object?>) return;
      final dossierRef = doc['dossierRef'];
      final titre = _map(doc['titres'])?['titrePrincipal'];
      if (dossierRef is String && titre is String) {
        _addTitleKey(titre, dossierRef);
      }
    } on Object {
      // Document illisible : il ne sert qu'au rattachement par intitulé.
    }
  }

  DossierIndex build() {
    // Une clé ne garde que les dossiers connus.
    titleKeys.updateAll((_, uids) => uids..retainAll(titles.keys));
    titleKeys.removeWhere((_, uids) => uids.isEmpty);
    return DossierIndex._(
      titles: titles,
      votes: votes,
      decisions: decisions,
      titleKeys: titleKeys,
      nonTexts: {
        for (final MapEntry(key: uid, value: codes) in topCodes.entries)
          if (codes.every((c) => !DossierIndex._isText(c))) uid,
      },
    );
  }
}

Map<String, Object?>? _map(Object? v) => v is Map<String, Object?> ? v : null;

Object? _actes(Map<String, Object?> m) =>
    _map(m['actesLegislatifs'])?['acteLegislatif'];

/// Le format officiel vient d'une conversion XML → JSON : un élément répété
/// une seule fois apparaît comme un objet, un élément absent comme `null`.
List<Object?> _list(Object? v) => switch (v) {
  null => const [],
  List<Object?> l => l,
  _ => [v],
};
