/// Rapport de fiabilité du filtrage par titre sur tout l'historique du dump.
library;

import 'classement.dart';
import 'csv.dart';
import 'dump.dart';

/// Sous-type des scrutins « l'ensemble … », pour repérer ce qui n'est pas un
/// vote sur un texte de loi entier.
String objetEnsemble(String titre) {
  final t = normaliserTitre(titre).replaceFirst(RegExp(r"^l'ensemble (de |du )(de )?(la )?"), '');
  if (RegExp(r'^(première|deuxième|troisième|quatrième) partie').hasMatch(t)) {
    return 'partie d\'une loi de finances';
  }
  if (t.startsWith('projet de loi')) return 'projet de loi';
  if (t.startsWith('proposition de loi')) return 'proposition de loi';
  if (t.startsWith('proposition de résolution')) return 'proposition de résolution';
  return 'autre';
}

String rapportFiltrage(List<ScrutinDump> scrutins) {
  final parCategorie = <Categorie, List<ScrutinDump>>{};
  for (final s in scrutins) {
    parCategorie.putIfAbsent(classer(s.titre), () => []).add(s);
  }
  int nb(Categorie c) => parCategorie[c]?.length ?? 0;

  final typo = scrutins.where((s) => s.titre.contains('’')).toList();
  final sauvesParNormalisation = typo.where((s) {
    final brut = s.titre.trim().toLowerCase();
    return classer(s.titre) != Categorie.nonClasse &&
        !RegExp(r"^(l'ensemble|la motion|la déclaration du gouvernement|le sous-amendement|l'amendement|l'article)")
            .hasMatch(brut);
  }).toList();

  final b = StringBuffer()
    ..writeln('# Filtrage par titre : ${scrutins.length} scrutins '
        '(${scrutins.first.dateScrutin} → ${scrutins.last.dateScrutin})')
    ..writeln()
    ..writeln('| Catégorie | Retenue par la règle du PRD | Scrutins |')
    ..writeln('|---|---|---:|');
  for (final c in Categorie.values) {
    b.writeln('| `${c.code}` | ${c.retenue ? 'oui' : 'non'} | ${nb(c)} |');
  }

  b
    ..writeln()
    ..writeln('Apostrophe typographique ’ : ${typo.length} titres en contiennent, '
        '${sauvesParNormalisation.length} ne seraient pas classés sans normalisation '
        '(dont ${sauvesParNormalisation.where((s) => classer(s.titre).retenue).length} retenus).')
    ..writeln();

  final ensembles = parCategorie[Categorie.ensemble] ?? [];
  final objets = <String, int>{};
  for (final s in ensembles) {
    objets.update(objetEnsemble(s.titre), (v) => v + 1, ifAbsent: () => 1);
  }
  b.writeln('Objet des votes « l\'ensemble … » : '
      '${objets.entries.map((e) => '${e.key} ${e.value}').join(', ')}.');

  final motions = parCategorie[Categorie.autreMotion] ?? [];
  b
    ..writeln()
    ..writeln('Autres motions (rejet préalable, etc.) : ${motions.length}, dont '
        '${motions.where((s) => s.sort == 'adopté').length} adoptées.');

  final censures = parCategorie[Categorie.motionCensure] ?? [];
  final moc = scrutins.where((s) => s.codeTypeVote == 'MOC').length;
  b.writeln('Motions de censure : ${censures.length} par le titre, $moc par le type de vote MOC.');

  final nonClasses = parCategorie[Categorie.nonClasse] ?? [];
  b
    ..writeln()
    ..writeln('## Titres non classés (${nonClasses.length})')
    ..writeln()
    ..writeln('| N° | Date | Type | Sort | Titre |')
    ..writeln('|---:|---|---|---|---|');
  for (final s in nonClasses) {
    b.writeln('| ${s.numero} | ${s.dateScrutin} | ${s.codeTypeVote} | ${s.sort} | '
        '${s.titre.replaceAll('|', '\\|')} |');
  }
  return b.toString();
}

String csvNonClasses(List<ScrutinDump> scrutins) {
  final b = StringBuffer('${ligneCsv(['numero', 'date_scrutin', 'type_vote', 'sort', 'titre'])}\n');
  for (final s in scrutins.where((s) => classer(s.titre) == Categorie.nonClasse)) {
    b.writeln(ligneCsv([s.numero, s.dateScrutin, s.codeTypeVote, s.sort, s.titre]));
  }
  return b.toString();
}
