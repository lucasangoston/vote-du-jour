import 'dart:convert';

import 'package:archive/archive.dart';

import 'decision_selector.dart' show normalizeTitle;
import 'dump_reader.dart' show DumpFormatException;

/// Archive des dossiers législatifs de la 17e législature (Licence Ouverte),
/// régénérée une fois par jour.
const dossiersDumpUrl =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/loi/dossiers_legislatifs/Dossiers_Legislatifs.json.zip';

/// Premier jour de la 17e législature : les dossiers ouverts sous une
/// législature précédente gardent leurs actes antérieurs, écartés des
/// adoptions à main levée.
final legislatureStart = DateTime.utc(2024, 7, 18);

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

/// Texte adopté par l'Assemblée sans scrutin public (à main levée), repéré
/// dans un dossier législatif : acte de décision de l'Assemblée en séance
/// (`AN1-DEBATS-DEC`, `ANLUNI-DEBATS-DEC`, `CMP-DEBATS-AN-DEC`…), au statut
/// d'adoption, qui ne cite aucun scrutin (`voteRefs` vide).
///
/// Un tel acte peut tout de même correspondre à un scrutin public que le
/// dossier ne cite pas : c'est au constructeur de l'index d'écarter ce
/// doublon (voir `buildDecisionIndex`).
class MainLeveeAdoption {
  const MainLeveeAdoption({
    required this.acteUid,
    required this.dossier,
    required this.lecture,
    required this.date,
    required this.isResolution,
    this.textTitle,
  });

  /// Identifiant de l'acte de décision, par exemple `L17-VD234087DEC` :
  /// identifiant stable de la décision publiée.
  final String acteUid;

  final Dossier dossier;

  /// Lecture de l'acte de premier niveau, si c'est une lecture à l'AN.
  final Lecture? lecture;

  /// Jour de la décision (heure de Paris), à minuit UTC.
  final DateTime date;

  /// Le dossier est une proposition de résolution (procédure
  /// « Résolution… »).
  final bool isResolution;

  /// Intitulé du texte adopté (`titrePrincipal` du document `BTA` associé à
  /// l'acte), s'il est connu.
  final String? textTitle;

  /// Intitulé officiel à publier : celui du texte adopté, sinon le titre du
  /// dossier.
  String get officialTitle => textTitle ?? dossier.title;
}

/// Codes `fam_code` des statuts d'adoption d'un acte de décision :
/// « adopté(e) », « adoptée avec modifications », « adopté(e) sans
/// modification », « modifié(e) » et « adopté(e), dans les conditions prévues
/// à l'article 45, alinéa 3, de la Constitution ». Sont exclus le rejet
/// (`TSORTF07`), l'adoption ou le rejet sans vote après un 49.3 (`TSORTF06`,
/// `TSORTF24`) et la résolution européenne devenue définitive sans débat en
/// séance (article 151-7 du Règlement, `TSORTF19`).
const _adoptionStatuses = {
  'TSORTF01',
  'TSORTF02',
  'TSORTF03',
  'TSORTF05',
  'TSORTF18',
};

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
    required List<_Adoption> adoptions,
    required Set<String> resolutions,
    required Map<String, String> textTitles,
    required Map<String, String> depositTexts,
  }) : _titles = titles,
       _votes = votes,
       _decisions = decisions,
       _titleKeys = titleKeys,
       _nonTexts = nonTexts,
       _adoptions = adoptions,
       _resolutions = resolutions,
       _textTitles = textTitles,
       _depositTexts = depositTexts;

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

  /// Actes de décision d'adoption de l'Assemblée qui ne citent aucun
  /// scrutin.
  final List<_Adoption> _adoptions;

  /// Dossiers de propositions de résolution.
  final Set<String> _resolutions;

  /// Intitulé des textes adoptés cités par [_adoptions], par identifiant de
  /// document.
  final Map<String, String> _textTitles;

  /// Texte déposé à l'Assemblée (premier acte `AN…-DEPOT`), par dossier.
  final Map<String, String> _depositTexts;

  /// Identifiant du texte déposé à l'Assemblée dans le dossier [dossierUid]
  /// (`PIONANR5L17B0284`), source des résumés (#9) : une proposition déposée
  /// à l'Assemblée a un exposé des motifs, un texte transmis par le Sénat
  /// n'a que ses articles. `null` si le dossier n'a pas de dépôt à
  /// l'Assemblée.
  String? depositText(String dossierUid) => _depositTexts[dossierUid];

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
        adoptions: [
          for (final a in json['adoptions'] as List)
            _Adoption.fromJson(a as List),
        ],
        resolutions: {...(json['resolutions'] as List).cast<String>()},
        textTitles: map(json['textTitles']).cast<String, String>(),
        depositTexts: map(json['depositTexts']).cast<String, String>(),
      );
    } on TypeError {
      throw const FormatException('Index des dossiers : format inattendu');
    }
  }

  /// Version 2 : ajout des adoptions à main levée (ticket #8). Version 3 :
  /// textes déposés, source des résumés (ticket #9). Un cache d'une version
  /// antérieure est refusé, donc reconstruit.
  static const _cacheVersion = 3;

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
      'adoptions': [for (final a in _adoptions) a.toJson()],
      'resolutions': _resolutions.toList()..sort(),
      'textTitles': _textTitles,
      'depositTexts': _depositTexts,
    };
  }

  /// Textes adoptés à main levée depuis [since] (début de la législature
  /// par défaut), dans l'ordre des dossiers. Voir [MainLeveeAdoption].
  List<MainLeveeAdoption> mainLeveeAdoptions({DateTime? since}) {
    final from = _day(since ?? legislatureStart);
    return [
      for (final a in _adoptions)
        if (a.day.compareTo(from) >= 0)
          if (dossier(a.dossier) case final d?)
            MainLeveeAdoption(
              acteUid: a.uid,
              dossier: d,
              lecture: Lecture.fromActeCode(a.top),
              date: DateTime.parse('${a.day}T00:00:00Z'),
              isResolution: _resolutions.contains(a.dossier),
              textTitle: a.text == null ? null : _textTitles[a.text],
            ),
    ];
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

/// Identifiant du dossier dont [url] est la page officielle
/// ([Dossier.url]), ou `null`.
String? dossierUidFromUrl(String? url) {
  if (url == null) return null;
  final match = RegExp(r'/dossiers/([A-Za-z0-9]+)$').firstMatch(url);
  return match?.group(1);
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

/// Le texte voté par le scrutin d'intitulé [titre] est-il, à quelques mots
/// près, l'un des [titles] (titre du dossier, du texte adopté) ?
///
/// Sert à écarter le doublon d'un vote à main levée quand le scrutin public
/// du même texte n'a pas pu être rattaché à son dossier : l'intitulé du
/// scrutin et celui du texte diffèrent parfois légèrement (« de Corse » /
/// « de la collectivité de Corse », « Haiti » / « Haïti », « relative à la
/// sûreté » / « relative au renforcement de la sûreté »). On compare les mots
/// significatifs, sans accents ni mots de procédure (« projet de loi
/// autorisant l'approbation de l'accord entre le Gouvernement… ») : au moins
/// 80 % des mots du plus court doivent figurer dans l'autre.
bool sameVotedText(String titre, Iterable<String> titles) {
  final voted = _votedText.firstMatch(normalizeTitle(titre))?.group(0);
  if (voted == null) return false;
  final a = _significantWords(voted.replaceFirst(_trailingParenthesis, ''));
  for (final title in titles) {
    final b = _significantWords(title);
    final (small, large) = a.length <= b.length ? (a, b) : (b, a);
    if (small.length < 2) continue;
    final shared = small.where(large.contains).length;
    if (shared >= 0.8 * small.length) return true;
  }
  return false;
}

Set<String> _significantWords(String title) => {
  for (final w in _withoutAccents(
    normalizeTitle(title).replaceAll('œ', 'oe'),
  ).split(RegExp('[^a-z0-9]+')))
    if (w.length > 2 && !_procedureWords.contains(w)) w,
};

String _withoutAccents(String s) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaceeeeiiiinooooouuuuyy';
  final out = StringBuffer();
  for (final c in s.split('')) {
    final i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString();
}

/// Mots de procédure et mots courts fréquents, sans valeur pour distinguer
/// deux textes.
const _procedureWords = {
  'projet', 'proposition', 'loi', 'organique', 'constitutionnelle', //
  'resolution', 'europeenne', 'autorisant', 'approbation', 'ratification',
  'accord', 'convention', 'avenant', 'traite', 'protocole', 'gouvernement',
  'republique', 'francaise', 'entre', 'relatif', 'relative', 'portant',
  'visant', 'tendant', 'les', 'des', 'aux', 'par', 'pour', 'sur', 'dans',
  'une', 'ses', 'leur', 'leurs', 'qui', 'que', 'est',
};

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
  final adoptions = <_Adoption>[];
  final resolutions = <String>{};
  final documentTitles = <String, String>{};
  final depositTexts = <String, String>{};

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
    final procedure = _map(d['procedureParlementaire'])?['libelle'];
    if (procedure is String && procedure.startsWith('Résolution')) {
      resolutions.add(uid);
    }
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
    // Premier dépôt à l'Assemblée (`AN1-DEPOT`, `ANLUNI-DEPOT`, `AN2-DEPOT`
    // d'un texte venu du Sénat…), dans l'ordre des actes.
    final deposited = acte['texteAssocie'];
    if (code is String &&
        code.startsWith('AN') &&
        code.endsWith('-DEPOT') &&
        deposited is String &&
        deposited.isNotEmpty) {
      depositTexts.putIfAbsent(uid, () => deposited);
    }
    if (code is String &&
        _isAssemblyDecision(code) &&
        date is String &&
        date.length >= 10) {
      // `dateActe` est en heure de Paris : les dix premiers caractères
      // donnent le jour du scrutin.
      decisions.putIfAbsent(uid, () => []).add((top, date.substring(0, 10)));
      final status = _map(acte['statutConclusion'])?['fam_code'];
      final acteUid = acte['uid'];
      if (_isAssemblyOnly(code) &&
          _adoptionStatuses.contains(status) &&
          _list(_map(acte['voteRefs'])?['voteRef']).isEmpty &&
          acteUid is String) {
        adoptions.add(
          _Adoption(
            uid: acteUid,
            dossier: uid,
            top: top,
            day: date.substring(0, 10),
            text: _adoptedText(acte),
          ),
        );
      }
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

  /// Décision prise par l'Assemblée elle-même : `AN…-DEBATS-DEC` ou
  /// `CMP-DEBATS-AN-DEC`. `CMP-DEBATS-DEC` est porté par le Sénat.
  static bool _isAssemblyOnly(String code) =>
      (code.startsWith('AN') && code.endsWith('-DEBATS-DEC')) ||
      code == 'CMP-DEBATS-AN-DEC';

  /// Texte adopté (`BTA`) associé à un acte de décision.
  static String? _adoptedText(Map<String, Object?> acte) {
    for (final t in _list(_map(acte['textesAssocies'])?['texteAssocie'])) {
      if (t is Map<String, Object?> &&
          t['typeTexte'] == 'BTA' &&
          t['refTexteAssocie'] is String) {
        return t['refTexteAssocie'] as String;
      }
    }
    return null;
  }

  void addDocument(String json) {
    try {
      final doc = (jsonDecode(json) as Map<String, Object?>)['document'];
      if (doc is! Map<String, Object?>) return;
      final dossierRef = doc['dossierRef'];
      final titre = _map(doc['titres'])?['titrePrincipal'];
      if (dossierRef is String && titre is String) {
        _addTitleKey(titre, dossierRef);
      }
      final docUid = doc['uid'];
      if (docUid is String && titre is String && titre.trim().isNotEmpty) {
        documentTitles[docUid] = titre.trim().replaceAll(RegExp(r'\s+'), ' ');
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
      adoptions: adoptions,
      resolutions: resolutions,
      // Seuls les intitulés des textes adoptés à main levée sont gardés.
      textTitles: {
        for (final a in adoptions)
          if (a.text case final t? when documentTitles.containsKey(t))
            t: documentTitles[t]!,
      },
      depositTexts: depositTexts,
    );
  }
}

/// Acte d'adoption sans scrutin, tel que gardé dans l'index (et son cache).
class _Adoption {
  const _Adoption({
    required this.uid,
    required this.dossier,
    required this.top,
    required this.day,
    this.text,
  });

  factory _Adoption.fromJson(List<Object?> json) => _Adoption(
    uid: json[0] as String,
    dossier: json[1] as String,
    top: json[2] as String,
    day: json[3] as String,
    text: json[4] as String?,
  );

  /// Identifiant de l'acte (`L17-VD…DEC`).
  final String uid;
  final String dossier;

  /// Code de l'acte de premier niveau (`AN1`, `ANLUNI`, `CMP`…).
  final String top;

  /// Jour (`AAAA-MM-JJ`, heure de Paris).
  final String day;

  /// Texte adopté (`BTA`), s'il est cité.
  final String? text;

  List<Object?> toJson() => [uid, dossier, top, day, text];
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
