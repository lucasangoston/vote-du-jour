import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Archive des comptes rendus des séances de la 17e législature (Licence
/// Ouverte, XML Syceron, ~59 Mo). Un compte rendu y arrive environ deux
/// jours après la séance.
const comptesRendusDumpUrl =
    'https://data.assemblee-nationale.fr/static/openData/repository/17/vp/syceronbrut/syseron.xml.zip';

/// Page d'un compte rendu sur le site de l'Assemblée (redirige vers la page
/// de la séance).
String compteRenduUrl(String uid) =>
    'https://www.assemblee-nationale.fr/dyn/17/comptes-rendus/seance/$uid';

/// Compte rendu d'une séance, réduit à ses explications de vote.
class CompteRendu {
  const CompteRendu({
    required this.uid,
    required this.date,
    required this.sections,
  });

  /// `CRSANR5L17S2027O1N020`.
  final String uid;

  /// Jour de la séance, à minuit UTC.
  final DateTime date;

  /// Sections d'explications de vote suivies d'au moins un vote sur
  /// l'ensemble au scrutin public.
  final List<ExplanationSection> sections;

  String get url => compteRenduUrl(uid);
}

/// Une section « Explications de vote » (ou « Explications de vote
/// communes ») et les votes sur l'ensemble qui la suivent. Une section
/// commune à deux textes est suivie de deux votes : elle vaut pour les deux.
class ExplanationSection {
  const ExplanationSection({
    required this.discussionTitle,
    required this.speeches,
    required this.votes,
  });

  /// Titre de la discussion (« Réponse intégrale aux violences… - Adapter
  /// l'autorité judiciaire… »).
  final String discussionTitle;

  /// Interventions des orateurs dont le groupe est connu, dans l'ordre.
  final List<Speech> speeches;

  /// Votes sur l'ensemble au scrutin public qui suivent la section.
  final List<WholeVote> votes;
}

/// Intervention d'un orateur (ses paragraphes réunis, interruptions et
/// didascalies retirées).
class Speech {
  const Speech({
    required this.speaker,
    required this.group,
    required this.text,
  });

  /// « Mme Clémentine Autain ».
  final String speaker;

  /// Sigle du groupe, tel qu'écrit après le nom (« EcoS »).
  final String group;

  final String text;
}

/// Un vote sur l'ensemble (ou sur l'article unique, ou sur une proposition
/// de résolution) au scrutin public.
class WholeVote {
  const WholeVote({required this.heading, this.announcement, this.result});

  /// « Vote sur l'ensemble (adapter l'autorité judiciaire…) ».
  final String heading;

  /// Phrase de la présidence qui met le texte aux voix (« Je mets aux voix
  /// l'ensemble de la proposition de loi organique visant à… »).
  final String? announcement;

  /// Résultat annoncé en séance, s'il est lisible.
  final ({int pour, int contre})? result;
}

/// Lit les comptes rendus de l'archive Syceron dont la séance tombe l'un des
/// jours [dates] (minuit UTC). Les autres ne sont pas analysés : seule leur
/// date est lue. Un compte rendu illisible est ignoré.
List<CompteRendu> readComptesRendusArchive(
  List<int> zipBytes, {
  required Set<DateTime> dates,
}) {
  final days = {for (final d in dates) _dayKey(d)};
  final result = <CompteRendu>[];
  for (final file in ZipDecoder().decodeBytes(zipBytes)) {
    final name = file.name.toLowerCase();
    if (!file.isFile || !name.endsWith('.xml')) continue;
    if (!name.contains('compterendu')) continue;
    final xml = utf8.decode(file.content, allowMalformed: true);
    final head = xml.length > 4000 ? xml.substring(0, 4000) : xml;
    final day = RegExp(r'<dateSeance>(\d{8})').firstMatch(head)?.group(1);
    if (day == null || !days.contains(day)) continue;
    if (parseCompteRendu(xml) case final cr?) result.add(cr);
  }
  return result;
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// Lit un compte rendu de séance (XML Syceron) ; `null` s'il est illisible.
///
/// Les points du compte rendu se suivent dans l'ordre de la séance. Une
/// section commence à un point « Explications de vote… » et se termine au
/// premier point qui n'est ni une suite des explications, ni un vote sur
/// l'ensemble, ni un rappel au règlement, ni une suspension : des
/// explications sur une motion de rejet, suivies de la discussion générale,
/// ne sont ainsi jamais rattachées au vote final du texte.
CompteRendu? parseCompteRendu(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on Object {
    return null;
  }
  final root = doc.rootElement;
  final uid = root.getElement('uid')?.innerText.trim();
  final rawDate = root
      .getElement('metadonnees')
      ?.getElement('dateSeance')
      ?.innerText
      .trim();
  if (uid == null || uid.isEmpty || rawDate == null || rawDate.length < 8) {
    return null;
  }
  final year = int.tryParse(rawDate.substring(0, 4));
  final month = int.tryParse(rawDate.substring(4, 6));
  final day = int.tryParse(rawDate.substring(6, 8));
  if (year == null || month == null || day == null) return null;
  final contenu = root.getElement('contenu');
  if (contenu == null) return null;

  final sections = <ExplanationSection>[];
  var discussionTitle = '';
  _SectionBuilder? open;
  void close() {
    if (open case final s? when s.votes.isNotEmpty && s.hasSpeeches) {
      sections.add(s.build());
    }
    open = null;
  }

  for (final point in contenu.findAllElements('point')) {
    final title = _text(point.getElement('texte'));
    final code = point.getAttribute('code_grammaire') ?? '';
    final level = point.getAttribute('nivpoint');
    final normalized = normalizeForMatching(title);
    if (normalized.startsWith('explications de vote')) {
      // Une suite (« Explications de vote (suite) », après un rappel au
      // règlement) complète la section encore ouverte.
      if (open == null || open!.votes.isNotEmpty) {
        close();
        open = _SectionBuilder(discussionTitle);
      }
      open!.addParagraphs(point.findElements('paragraphe'));
    } else if (code.startsWith('VOTE_ENS_')) {
      // Scrutin public (`_S_`) ; un vote à main levée (`_ML_`) n'a pas de
      // vote par groupe et ne reçoit pas d'arguments.
      if (open != null && code.contains('_S_')) {
        open!.votes.add(_wholeVote(title, point.findElements('paragraphe')));
      } else {
        close();
      }
    } else if (level == '99' ||
        code.startsWith('RAP_REGLEMENT') ||
        code.startsWith('SUSP')) {
      // Incident de séance : la section reste ouverte.
    } else {
      close();
      if (level == '1') discussionTitle = title;
    }
  }
  close();
  return CompteRendu(
    uid: uid,
    date: DateTime.utc(year, month, day),
    sections: sections,
  );
}

class _SectionBuilder {
  _SectionBuilder(this.discussionTitle);

  final String discussionTitle;
  final votes = <WholeVote>[];

  /// Interventions, dans l'ordre de première prise de parole.
  final _texts = <String, StringBuffer>{};
  final _names = <String, String>{};
  final _groups = <String, String>{};

  bool get hasSpeeches => _texts.keys.any(_groups.containsKey);

  /// Ajoute les paragraphes des orateurs. Le groupe d'un orateur est écrit
  /// entre parenthèses après son nom la première fois qu'il parle
  /// (« Mme Clémentine Autain (EcoS) ») ; ses paragraphes suivants sont
  /// reconnus par son identifiant d'acteur. Interruptions, présidence et
  /// orateurs sans groupe (ministres, rapporteurs) sont ignorés.
  void addParagraphs(Iterable<XmlElement> paragraphs) {
    for (final p in paragraphs) {
      final code = p.getAttribute('code_grammaire') ?? '';
      if (code.startsWith('INTERRUPTION')) continue;
      if (p.getAttribute('roledebat') == 'president') continue;
      final names = [
        for (final o in p.findAllElements('orateur'))
          o.getElement('nom')?.innerText.trim() ?? '',
      ];
      if (names.length != 1 || names.single.isEmpty) continue;
      final name = names.single;
      final group = RegExp(r'\(([^()]+)\)\s*$').firstMatch(name)?.group(1);
      final plainName = name
          .replaceAll(RegExp(r'\s*\([^()]*\)\s*$'), '')
          .replaceAll(RegExp(r'[\s,]+$'), '');
      final key = p.getAttribute('id_acteur') ?? plainName;
      if (group != null && !_groups.containsKey(key)) {
        _groups[key] = group.trim();
        _names[key] = plainName.replaceAll(RegExp(r'\s*\([^()]*\)\s*$'), '');
      }
      final text = _text(p.getElement('texte'));
      if (text.isEmpty) continue;
      final buffer = _texts.putIfAbsent(key, StringBuffer.new);
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }
  }

  ExplanationSection build() => ExplanationSection(
    discussionTitle: discussionTitle,
    speeches: [
      for (final MapEntry(:key, :value) in _texts.entries)
        if (_groups[key] case final group?)
          Speech(
            speaker: _names[key] ?? key,
            group: group,
            text: value.toString(),
          ),
    ],
    votes: List.unmodifiable(votes),
  );
}

WholeVote _wholeVote(String heading, Iterable<XmlElement> paragraphs) {
  String? announcement;
  ({int pour, int contre})? result;
  for (final p in paragraphs) {
    final text = _text(p.getElement('texte'));
    if (announcement == null && text.startsWith('Je mets aux voix')) {
      announcement = text;
    }
    if (result == null && text.startsWith('Voici le résultat du scrutin')) {
      final pour = RegExp(r'Pour l.adoption\s+(\d+)').firstMatch(text);
      final contre = RegExp(r'Contre\s+(\d+)').firstMatch(text);
      if (pour != null && contre != null) {
        result = (
          pour: int.parse(pour.group(1)!),
          contre: int.parse(contre.group(1)!),
        );
      }
    }
  }
  return WholeVote(
    heading: heading,
    announcement: announcement,
    result: result,
  );
}

/// Texte d'un élément `texte`, espaces normalisés, sans les didascalies en
/// italique entre parenthèses (« (Applaudissements sur les bancs…) »), que
/// le compte rendu découpe parfois en plusieurs éléments `italique`.
String _text(XmlElement? element) {
  if (element == null) return '';
  const start = '\u0001';
  const end = '\u0002';
  final buffer = StringBuffer();
  void walk(XmlNode node, {required bool italic}) {
    for (final child in node.children) {
      if (child is XmlText || child is XmlCDATA) {
        buffer.write(child.value);
      } else if (child is XmlElement) {
        final name = child.name.local;
        if (name == 'br') {
          buffer.write(' ');
        } else if (name == 'italique' && !italic) {
          buffer.write(start);
          walk(child, italic: true);
          buffer.write(end);
        } else {
          walk(child, italic: italic);
        }
      }
    }
  }

  walk(element, italic: false);
  return buffer
      .toString()
      // Italiques consécutives : une seule didascalie.
      .replaceAll(RegExp('$end\\s*$start'), ' ')
      .replaceAllMapped(
        RegExp('$start([^$end]*)$end'),
        (m) => RegExp(r'^\s*\(.*\)\s*$', dotAll: true).hasMatch(m.group(1)!)
            ? ' '
            : m.group(1)!,
      )
      .replaceAll(RegExp('[$start$end]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Minuscules, sans accents, apostrophes droites, espaces normalisés : pour
/// comparer des intitulés.
String normalizeForMatching(String text) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ’‘';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa\'\'';
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final c = String.fromCharCode(rune);
    final i = from.indexOf(c);
    if (i < 0) {
      buffer.write(c);
    } else if (c == 'œ') {
      buffer.write('oe');
    } else if (c == 'æ') {
      buffer.write('ae');
    } else {
      buffer.write(to[i]);
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
