import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:vote_contract/vote_contract.dart';

import 'scrutin.dart';

/// Le jeu de données ne respecte pas le format attendu.
class DumpFormatException implements Exception {
  DumpFormatException(this.source, this.message);

  /// Fichier de l'archive en cause.
  final String source;
  final String message;

  @override
  String toString() => 'DumpFormatException ($source) : $message';
}

/// Lit l'archive `Scrutins.json.zip` de l'Assemblée nationale (un fichier JSON
/// par scrutin) et renvoie tous les scrutins qu'elle contient.
///
/// Lève [DumpFormatException] si un fichier JSON n'a pas le format attendu :
/// mieux vaut garder l'index déjà publié que publier des données fausses.
List<Scrutin> readScrutinsArchive(List<int> zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  return [
    for (final file in archive)
      if (file.isFile && file.name.toLowerCase().endsWith('.json'))
        parseScrutinJson(utf8.decode(file.content), source: file.name),
  ];
}

/// Lit le JSON d'un scrutin (un fichier du jeu de données).
Scrutin parseScrutinJson(String json, {String source = 'scrutin'}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw DumpFormatException(source, 'JSON invalide : ${e.message}');
  }
  final r = _Reader(source);
  final s = r.map(r.map(decoded, 'racine')['scrutin'], 'scrutin');
  final synthese = r.map(s['syntheseVote'], 'syntheseVote');
  final objet = s['objet'];
  final dossier = objet is Map<String, Object?>
      ? objet['dossierLegislatif']
      : null;
  return Scrutin(
    uid: r.string(s['uid'], 'uid'),
    numero: r.integer(s['numero'], 'numero'),
    date: r.date(s['dateScrutin'], 'dateScrutin'),
    titre: r.string(s['titre'], 'titre'),
    codeTypeVote: r.string(
      r.map(s['typeVote'], 'typeVote')['codeTypeVote'],
      'typeVote.codeTypeVote',
    ),
    libelleTypeVote: r.string(
      r.map(s['typeVote'], 'typeVote')['libelleTypeVote'],
      'typeVote.libelleTypeVote',
    ),
    result: r.result(r.map(s['sort'], 'sort')['code'], 'sort.code'),
    decompte: r.decompte(synthese['decompte'], 'syntheseVote.decompte'),
    dossierRef:
        dossier is Map<String, Object?> && dossier['dossierRef'] is String
        ? dossier['dossierRef'] as String
        : null,
    seanceRef: s['seanceRef'] is String && (s['seanceRef'] as String).isNotEmpty
        ? s['seanceRef'] as String
        : null,
    groupVotes: [
      for (final g in r.list(
        r.map(
          r.map(
            r.map(s['ventilationVotes'], 'ventilationVotes')['organe'],
            'ventilationVotes.organe',
          )['groupes'],
          'groupes',
        )['groupe'],
        'groupes.groupe',
      ))
        r.groupVote(g),
    ],
  );
}

/// Lecture défensive : chaque écart au format attendu lève une
/// [DumpFormatException] qui nomme le fichier et le champ.
class _Reader {
  _Reader(this.source);

  final String source;

  Never _fail(String field, Object? value) =>
      throw DumpFormatException(source, '$field inattendu : $value');

  Map<String, Object?> map(Object? v, String field) =>
      v is Map<String, Object?> ? v : _fail(field, v);

  /// Le format officiel vient d'une conversion XML → JSON : un élément répété
  /// une seule fois peut apparaître comme un objet au lieu d'une liste.
  List<Object?> list(Object? v, String field) => switch (v) {
    List<Object?> l => l,
    Map<String, Object?> m => [m],
    _ => _fail(field, v),
  };

  String string(Object? v, String field) =>
      v is String && v.trim().isNotEmpty ? v.trim() : _fail(field, v);

  int integer(Object? v, String field) =>
      (v is String ? int.tryParse(v) : null) ?? _fail(field, v);

  DateTime date(Object? v, String field) {
    final match = v is String
        ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v)
        : null;
    if (match == null) _fail(field, v);
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  VoteResult result(Object? v, String field) => switch (v) {
    'adopté' => VoteResult.adopte,
    'rejeté' => VoteResult.rejete,
    _ => _fail(field, v),
  };

  Decompte decompte(Object? v, String field) {
    final m = map(v, field);
    return Decompte(
      pour: integer(m['pour'], '$field.pour'),
      contre: integer(m['contre'], '$field.contre'),
      abstentions: integer(m['abstentions'], '$field.abstentions'),
      nonVotants: integer(m['nonVotants'], '$field.nonVotants'),
    );
  }

  GroupVote groupVote(Object? v) {
    final g = map(v, 'groupe');
    final vote = map(g['vote'], 'groupe.vote');
    return GroupVote(
      organeRef: string(g['organeRef'], 'groupe.organeRef'),
      positionMajoritaire: string(
        vote['positionMajoritaire'],
        'groupe.vote.positionMajoritaire',
      ),
      decompte: decompte(vote['decompteVoix'], 'groupe.vote.decompteVoix'),
      membres: int.tryParse('${g['nombreMembresGroupe']}'),
      votants: nominalVotes(vote['decompteNominatif']),
    );
  }

  /// Vote nominatif d'un groupe (#71). Lecture tolérante : un bloc absent ou
  /// un votant illisible est ignoré, sans rendre le scrutin illisible ; les
  /// sièges, vérifiés contre le décompte, ne seront alors pas publiés.
  List<NominalVote> nominalVotes(Object? v) {
    if (v is! Map<String, Object?>) return const [];
    return [
      for (final (key, vote) in const [
        ('pours', SeatVote.pour),
        ('contres', SeatVote.contre),
        ('abstentions', SeatVote.abstention),
        ('nonVotants', SeatVote.nonVotant),
      ])
        if (v[key] case {'votant': final votants})
          for (final votant in switch (votants) {
            List<Object?> l => l,
            Map<String, Object?> m => [m],
            _ => const <Object?>[],
          })
            if (votant case {'acteurRef': final String acteurRef})
              NominalVote(
                acteurRef: acteurRef,
                place: int.tryParse('${votant['numPlace']}'),
                vote: vote,
              ),
    ];
  }
}
