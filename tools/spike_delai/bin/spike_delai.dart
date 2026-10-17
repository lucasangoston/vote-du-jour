/// Spike #15 : mesure du délai de publication des scrutins.
///
///   dart run bin/spike_delai.dart releve  <dossier-donnees>
///   dart run bin/spike_delai.dart resume  <dossier-donnees>
///   dart run bin/spike_delai.dart filtrage <Scrutins.json.zip> [non_classes.csv]
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spike_delai/src/dump.dart';
import 'package:spike_delai/src/liste_site.dart';
import 'package:spike_delai/src/rapport_filtrage.dart';
import 'package:spike_delai/src/releve.dart';
import 'package:spike_delai/src/resume.dart';

const userAgent =
    'vote-du-jour-spike/0.1 (mesure ponctuelle; +https://github.com/lucasangoston/vote-du-jour)';
const urlListe = 'https://www.assemblee-nationale.fr/dyn/17/scrutins';
const urlDump =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/loi/scrutins/Scrutins.json.zip';

/// 50 scrutins par page : plus que ce qu'une séance produit en 5 minutes.
const parPage = 50;
const pagesMax = 3;

Future<void> main(List<String> args) async {
  if (args.isEmpty) return _usage();
  switch (args.first) {
    case 'releve' when args.length == 2:
      exitCode = await releve(DossierDonnees(args[1]));
    case 'resume' when args.length == 2:
      final dossier = DossierDonnees(args[1]);
      final heures = File('${args[1]}/heures_vote.csv');
      stdout.write(resumer(
        dossier.lireReleve(),
        dossier.lirePassages(),
        heures.existsSync() ? lireHeuresVote(heures.readAsStringSync()) : {},
      ));
    case 'filtrage' when args.length >= 2:
      final scrutins = lireDump(File(args[1]).readAsBytesSync());
      stdout.write(rapportFiltrage(scrutins));
      if (args.length == 3) File(args[2]).writeAsStringSync(csvNonClasses(scrutins));
    default:
      _usage();
  }
}

void _usage() {
  stderr.writeln('usage : spike_delai releve|resume <dossier> | filtrage <zip> [csv]');
  exitCode = 64;
}

/// Un passage du cron : une lecture de la liste (plus une ou deux pages
/// suivantes en cas de débordement) et une requête conditionnelle sur le dump.
/// Les erreurs sont consignées dans passages.csv sans faire échouer le job,
/// sauf si rien n'a pu être lu.
Future<int> releve(DossierDonnees dossier) async {
  final client = HttpClient()
    ..userAgent = userAgent
    ..connectionTimeout = const Duration(seconds: 30);
  final etat = dossier.lireEtat();
  final lignes = dossier.lireReleve();
  final maintenant = DateTime.now().toUtc();
  final messages = <String>[];
  var statut = 'ok';
  var pages = 0;
  int? numeroMax;
  var nouveaux = 0;

  try {
    final lu = <ScrutinSite>[];
    for (var page = 1; page <= pagesMax; page++) {
      final html = await _get(client, '$urlListe?page=$page&limit=$parPage');
      final items = lireListe(html.corps);
      pages++;
      lu.addAll(items);
      if (!pageADebordement(etat, lignes, lu)) break;
      if (page == pagesMax) messages.add('débordement : des scrutins ont pu être manqués');
    }
    numeroMax = lu.map((s) => s.numero).reduce((a, b) => a > b ? a : b);
    nouveaux = integrerListe(etat, lignes, lu, maintenant).length;
  } catch (e) {
    statut = 'erreur_site';
    messages.add('site : $e');
  }

  var etatDump = 'inchange';
  try {
    final r = await _getOctets(client, urlDump, siModifieDepuis: etat.dumpLastModified);
    if (r != null) {
      final numeros = numerosDuDump(r.octets);
      final attendus = lignes.where((l) => l.apparitionDump == null).map((l) => l.numero).toSet();
      final dates = {
        for (final s in lireDump(r.octets, seulement: attendus.intersection(numeros)))
          s.numero: s.dateScrutin,
      };
      final lastModified = r.lastModified == null ? maintenant : HttpDate.parse(r.lastModified!);
      final n = integrerDump(lignes, dates, lastModified);
      etat.dumpLastModified = r.lastModified;
      etatDump = 'maj ($n scrutins relevés, ${numeros.length} au total)';
    }
  } catch (e) {
    etatDump = 'erreur';
    messages.add('dump : $e');
  }

  client.close(force: true);
  dossier.ecrire(etat, lignes);
  dossier.ajouterPassage([
    isoUtc(maintenant),
    statut,
    pages,
    numeroMax ?? '',
    nouveaux,
    etatDump,
    messages.join(' | '),
  ]);
  stdout.writeln('$statut, $nouveaux nouveau(x), dump $etatDump ${messages.join(' | ')}');
  return statut == 'ok' || etatDump != 'erreur' ? 0 : 1;
}

class _Reponse {
  _Reponse(this.corps);
  final String corps;
}

class _Octets {
  _Octets(this.octets, this.lastModified);
  final List<int> octets;
  final String? lastModified;
}

Future<_Reponse> _get(HttpClient client, String url) async {
  final req = await client.getUrl(Uri.parse(url));
  final res = await req.close().timeout(const Duration(seconds: 60));
  final corps = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
  return _Reponse(corps);
}

/// GET conditionnel : renvoie null si le serveur répond 304.
Future<_Octets?> _getOctets(HttpClient client, String url, {String? siModifieDepuis}) async {
  final req = await client.getUrl(Uri.parse(url));
  if (siModifieDepuis != null) req.headers.set(HttpHeaders.ifModifiedSinceHeader, siModifieDepuis);
  final res = await req.close().timeout(const Duration(minutes: 5));
  if (res.statusCode == 304) {
    await res.drain<void>();
    return null;
  }
  if (res.statusCode != 200) {
    await res.drain<void>();
    throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
  }
  final octets = BytesBuilder(copy: false);
  await for (final morceau in res) {
    octets.add(morceau);
  }
  return _Octets(octets.takeBytes(), res.headers.value(HttpHeaders.lastModifiedHeader));
}
