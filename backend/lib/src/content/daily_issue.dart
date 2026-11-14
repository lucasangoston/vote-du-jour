import 'dart:convert';

import 'post_text.dart';

/// Label des issues du jour de la content factory (#111).
const contentLabel = 'content';

/// Label qui déclenche la publication des brouillons cochés (#112).
const publishLabel = 'publier';

/// Version du format de l'issue, lue par la publication (#112).
const dailyIssueFormat = 'content-factory:v1';

/// Titre de l'issue du jour : « Posts du 14 novembre 2026 ».
String dailyIssueTitle(DateTime parisDay) =>
    'Posts du ${frenchLongDate(parisDay)}';

/// Clé de l'image d'un brouillon dans le bucket public.
String draftImageKey(DateTime parisDay, String decisionId) =>
    'content/${_isoDay(parisDay)}/$decisionId.png';

String _isoDay(DateTime d) =>
    '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';

/// Un brouillon de post dans l'issue du jour.
class Draft {
  const Draft({
    required this.decisionId,
    required this.sourceUrl,
    required this.title,
    this.text,
    this.alt,
    this.imageUrl,
    this.checked = false,
    this.postUrl,
  });

  final String decisionId;

  /// Page officielle du scrutin, pour vérifier les chiffres.
  final String sourceUrl;

  /// Titre de la carte ; `null` : titre à écrire (#109), la carte et les
  /// textes sont produits à la publication.
  final String? title;

  final String? text;
  final String? alt;
  final String? imageUrl;

  /// Case « Publier ce post » cochée.
  final bool checked;

  /// Lien du post publié (#112) : un brouillon publié ne l'est jamais deux
  /// fois.
  final String? postUrl;

  bool get needsTitle => title == null;
}

/// Corps de l'issue du jour : un bloc par brouillon, case à cocher, image,
/// texte et texte alternatif modifiables, lien de vérification, original
/// caché (pour compter les corrections, #113).
String renderDailyIssue(DateTime parisDay, List<Draft> drafts) {
  final out = StringBuffer()
    ..writeln('<!-- $dailyIssueFormat day:${_isoDay(parisDay)} -->')
    ..writeln(
      'Brouillons du jour. Coche les posts à publier, corrige le texte si '
      'besoin, puis pose le label `$publishLabel`. Fermer l\'issue sans ce '
      'label jette tout.',
    );
  for (final d in drafts) {
    out
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('<!-- decision:${d.decisionId} -->')
      ..writeln('### ${d.title ?? 'Titre à écrire'}')
      ..writeln()
      ..writeln('- [ ] Publier ce post')
      ..writeln();
    if (d.needsTitle) {
      out
        ..writeln(
          'Le titre du résumé ne tient pas sur la carte. Écris un titre '
          'court ci-dessous : la carte et les textes seront produits à la '
          'publication.',
        )
        ..writeln()
        ..writeln('**Titre**')
        ..writeln()
        ..writeln(_fence(''));
    } else {
      out
        ..writeln('![Carte](${d.imageUrl})')
        ..writeln()
        ..writeln('**Texte du post** (${postLength(d.text!)} / $postMaxLength)')
        ..writeln()
        ..writeln(_fence(d.text!))
        ..writeln()
        ..writeln('**Texte alternatif**')
        ..writeln()
        ..writeln(_fence(d.alt!));
    }
    out
      ..writeln()
      ..writeln(
        'Vérifier les chiffres : [page officielle du scrutin]'
        '(${d.sourceUrl})',
      )
      ..writeln()
      ..writeln('<!-- original:${_encodeOriginal(d)} -->');
  }
  return out.toString();
}

String _fence(String body) => '```text\n$body\n```';

String _encodeOriginal(Draft d) => base64Url.encode(
  utf8.encode(jsonEncode({'title': d.title, 'text': d.text, 'alt': d.alt})),
);

final _decisionMarker = RegExp(r'<!-- decision:([A-Za-z0-9-]+) -->');
final _checkbox = RegExp(r'^- \[([ xX])\] Publier ce post', multiLine: true);
final _textFence = RegExp(r'```text\n([\s\S]*?)\n?```');
final _image = RegExp(r'!\[Carte\]\(([^)\s]+)\)');
final _source = RegExp(r'\[page officielle du scrutin\]\(([^)\s]+)\)');
final _posted = RegExp(r'Publié : (\S+)');
final _original = RegExp(r'<!-- original:([A-Za-z0-9_=-]+) -->');

/// Brouillons de l'issue [body], tels qu'édités : case, textes, titre écrit.
/// Un bloc illisible est ignoré.
List<Draft> parseDailyIssue(String body) {
  final markers = _decisionMarker.allMatches(body).toList();
  return [
    for (var i = 0; i < markers.length; i++)
      ?_parseBlock(
        markers[i].group(1)!,
        body.substring(
          markers[i].end,
          i + 1 < markers.length ? markers[i + 1].start : body.length,
        ),
      ),
  ];
}

Draft? _parseBlock(String id, String block) {
  final original = _decodeOriginal(block);
  final source = _source.firstMatch(block)?.group(1);
  if (original == null || source == null) return null;
  final fences = [for (final m in _textFence.allMatches(block)) m.group(1)!];
  final checked = _checkbox.firstMatch(block)?.group(1)?.trim().isNotEmpty;
  final needsTitle = original['title'] == null;
  final writtenTitle = needsTitle && fences.isNotEmpty
      ? fences.first.trim()
      : null;
  return Draft(
    decisionId: id,
    sourceUrl: source,
    title: needsTitle
        ? (writtenTitle == null || writtenTitle.isEmpty ? null : writtenTitle)
        : original['title'],
    text: needsTitle ? null : (fences.isNotEmpty ? fences[0] : null),
    alt: needsTitle ? null : (fences.length > 1 ? fences[1] : null),
    imageUrl: _image.firstMatch(block)?.group(1),
    checked: checked ?? false,
    postUrl: _posted.firstMatch(block)?.group(1),
  );
}

/// Brouillon tel que généré, d'après l'original caché du bloc de [id] dans
/// [body] ; `null` s'il est absent.
Map<String, String?>? originalDraft(String body, String id) {
  final markers = _decisionMarker.allMatches(body).toList();
  for (var i = 0; i < markers.length; i++) {
    if (markers[i].group(1) != id) continue;
    return _decodeOriginal(
      body.substring(
        markers[i].end,
        i + 1 < markers.length ? markers[i + 1].start : body.length,
      ),
    );
  }
  return null;
}

Map<String, String?>? _decodeOriginal(String block) {
  final raw = _original.firstMatch(block)?.group(1);
  if (raw == null) return null;
  try {
    final json = jsonDecode(utf8.decode(base64Url.decode(raw)));
    if (json is! Map) return null;
    return {
      for (final k in ['title', 'text', 'alt'])
        k: json[k] is String ? json[k] as String : null,
    };
  } on FormatException {
    return null;
  }
}

/// Ids des décisions présentes dans les issues du jour [bodies] (publiées,
/// jetées ou en attente) : la sélection (#108) ne les propose plus.
Set<String> handledDecisionIds(Iterable<String> bodies) => {
  for (final body in bodies)
    if (body.contains(dailyIssueFormat))
      for (final m in _decisionMarker.allMatches(body)) m.group(1)!,
};
