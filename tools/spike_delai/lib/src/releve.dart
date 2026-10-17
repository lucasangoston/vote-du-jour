/// Relevé des apparitions de scrutins : logique pure (sans réseau) et
/// lecture/écriture des fichiers du dossier de données.
///
/// Fichiers du dossier de données :
/// - `releve.csv` : une ligne par scrutin apparu pendant la mesure ;
/// - `passages.csv` : une ligne par passage du cron (pour connaître la
///   cadence réelle, GitHub retardant souvent les crons) ;
/// - `etat.json` : numéro de référence initial et Last-Modified du dump.
library;

import 'dart:convert';
import 'dart:io';

import 'classement.dart';
import 'csv.dart';
import 'liste_site.dart';

class LigneReleve {
  LigneReleve({
    required this.numero,
    required this.apparitionSite,
    required this.passagePrecedent,
    required this.seance,
    required this.titre,
    required this.categorie,
    this.apparitionDump,
    this.dateScrutin = '',
  });

  final int numero;

  /// Passage où le scrutin a été vu pour la première fois sur le site (UTC).
  final DateTime apparitionSite;

  /// Passage réussi précédent (UTC) : le scrutin est apparu entre ce passage
  /// et [apparitionSite]. Nul pour le premier passage après l'initialisation.
  final DateTime? passagePrecedent;

  final String seance;
  final String titre;
  final String categorie;

  /// Last-Modified (UTC) de la première version du dump qui contient ce
  /// scrutin.
  DateTime? apparitionDump;

  /// Date du scrutin selon le dump (AAAA-MM-JJ).
  String dateScrutin;

  static const entete = [
    'numero',
    'apparition_site_utc',
    'passage_precedent_utc',
    'seance',
    'categorie',
    'apparition_dump_utc',
    'date_scrutin',
    'titre',
  ];

  List<Object?> enColonnes() => [
        numero,
        _iso(apparitionSite),
        _iso(passagePrecedent),
        seance,
        categorie,
        _iso(apparitionDump),
        dateScrutin,
        titre,
      ];

  static LigneReleve depuisMap(Map<String, String> m) => LigneReleve(
        numero: int.parse(m['numero']!),
        apparitionSite: DateTime.parse(m['apparition_site_utc']!),
        passagePrecedent: _date(m['passage_precedent_utc']),
        seance: m['seance'] ?? '',
        titre: m['titre'] ?? '',
        categorie: m['categorie'] ?? '',
        apparitionDump: _date(m['apparition_dump_utc']),
        dateScrutin: m['date_scrutin'] ?? '',
      );
}

class Etat {
  Etat({this.numeroReference, this.dernierPassageReussi, this.dumpLastModified});

  /// Plus grand numéro visible lors du tout premier passage : les scrutins
  /// jusqu'à ce numéro existaient avant la mesure et sont ignorés.
  int? numeroReference;

  DateTime? dernierPassageReussi;

  /// En-tête Last-Modified brut (format HTTP) de la dernière version du dump
  /// téléchargée, renvoyé tel quel dans If-Modified-Since.
  String? dumpLastModified;

  Map<String, Object?> versJson() => {
        'numero_reference': numeroReference,
        'dernier_passage_reussi_utc': _iso(dernierPassageReussi),
        'dump_last_modified': dumpLastModified,
      };

  static Etat depuisJson(Map<String, dynamic> j) => Etat(
        numeroReference: j['numero_reference'] as int?,
        dernierPassageReussi: _date(j['dernier_passage_reussi_utc'] as String?),
        dumpLastModified: j['dump_last_modified'] as String?,
      );
}

/// Intègre une lecture de la liste du site. Renvoie les lignes ajoutées.
///
/// Au tout premier passage, seul le numéro de référence est enregistré.
List<LigneReleve> integrerListe(
  Etat etat,
  List<LigneReleve> releve,
  List<ScrutinSite> liste,
  DateTime maintenant,
) {
  if (liste.isEmpty) return const [];
  final maxListe = liste.map((s) => s.numero).reduce((a, b) => a > b ? a : b);
  if (etat.numeroReference == null) {
    etat.numeroReference = maxListe;
    etat.dernierPassageReussi = maintenant;
    return const [];
  }
  final connus = releve.map((l) => l.numero).toSet();
  final ajouts = <LigneReleve>[];
  for (final s in liste.reversed) {
    if (s.numero <= etat.numeroReference! || connus.contains(s.numero)) continue;
    ajouts.add(LigneReleve(
      numero: s.numero,
      apparitionSite: maintenant,
      passagePrecedent: etat.dernierPassageReussi,
      seance: s.seance,
      titre: titreSansPrefixe(s.titre),
      categorie: classer(s.titre).code,
    ));
  }
  releve.addAll(ajouts);
  releve.sort((a, b) => a.numero.compareTo(b.numero));
  etat.dernierPassageReussi = maintenant;
  return ajouts;
}

/// Vrai si la page lue ne recoupe pas les numéros déjà connus : des scrutins
/// ont pu tomber sur la page suivante, qu'il faut alors lire aussi.
bool pageADebordement(Etat etat, List<LigneReleve> releve, List<ScrutinSite> page) {
  if (etat.numeroReference == null || page.isEmpty) return false;
  final plusAncien = page.map((s) => s.numero).reduce((a, b) => a < b ? a : b);
  final dejaConnu =
      [etat.numeroReference!, ...releve.map((l) => l.numero)].reduce((a, b) => a > b ? a : b);
  return plusAncien > dejaConnu + 1;
}

/// Note l'apparition dans le dump des scrutins relevés qui y figurent.
/// [datesDump] associe numéro -> date du scrutin selon le dump.
/// Renvoie le nombre de lignes mises à jour.
int integrerDump(
  List<LigneReleve> releve,
  Map<int, String> datesDump,
  DateTime lastModified,
) {
  var n = 0;
  for (final l in releve) {
    if (l.apparitionDump != null || !datesDump.containsKey(l.numero)) continue;
    l.apparitionDump = lastModified;
    l.dateScrutin = datesDump[l.numero]!;
    n++;
  }
  return n;
}

class DossierDonnees {
  DossierDonnees(this.chemin);

  final String chemin;

  File get _releve => File('$chemin/releve.csv');
  File get _passages => File('$chemin/passages.csv');
  File get _etat => File('$chemin/etat.json');

  static const entetePassages = [
    'horodatage_utc',
    'statut',
    'pages_lues',
    'numero_max_site',
    'nouveaux',
    'dump',
    'message',
  ];

  Etat lireEtat() => _etat.existsSync()
      ? Etat.depuisJson(jsonDecode(_etat.readAsStringSync()) as Map<String, dynamic>)
      : Etat();

  List<LigneReleve> lireReleve() => _releve.existsSync()
      ? lireCsvAvecEntete(_releve.readAsStringSync()).map(LigneReleve.depuisMap).toList()
      : <LigneReleve>[];

  List<Map<String, String>> lirePassages() =>
      _passages.existsSync() ? lireCsvAvecEntete(_passages.readAsStringSync()) : [];

  void ecrire(Etat etat, List<LigneReleve> releve) {
    Directory(chemin).createSync(recursive: true);
    _etat.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(etat.versJson())}\n');
    final buf = StringBuffer('${ligneCsv(LigneReleve.entete)}\n');
    for (final l in releve) {
      buf.writeln(ligneCsv(l.enColonnes()));
    }
    _releve.writeAsStringSync(buf.toString());
  }

  void ajouterPassage(List<Object?> colonnes) {
    Directory(chemin).createSync(recursive: true);
    if (!_passages.existsSync()) {
      _passages.writeAsStringSync('${ligneCsv(entetePassages)}\n');
    }
    _passages.writeAsStringSync('${ligneCsv(colonnes)}\n', mode: FileMode.append);
  }
}

String _iso(DateTime? d) =>
    d == null ? '' : d.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

DateTime? _date(String? s) => (s == null || s.isEmpty) ? null : DateTime.parse(s).toUtc();

String isoUtc(DateTime d) => _iso(d);
