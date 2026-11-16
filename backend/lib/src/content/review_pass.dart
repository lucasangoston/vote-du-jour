import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

import '../object_store.dart';
import 'daily_issue.dart';
import 'post_text.dart';
import 'proofreader.dart';

/// Marqueur du commentaire de relecture de l'issue du jour (#122) : un seul
/// commentaire, mis à jour à chaque modification.
const reviewCommentMarker = '<!-- content-review -->';

/// Écrit dans `<dir>/<id>.post.txt` le texte de chaque carte rendue de la
/// sélection (statut `ok`) et dans `<dir>/<id>.reply.txt` sa réponse en fil,
/// pour l'aperçu Bluesky de l'issue du jour.
Future<void> writeDraftTexts(Directory dir) async {
  final ids =
      (jsonDecode(await File('${dir.path}/selection.json').readAsString())
              as List)
          .cast<String>();
  for (final id in ids) {
    final status =
        jsonDecode(await File('${dir.path}/$id.png.json').readAsString())
            as Map<String, Object?>;
    if (status['status'] != 'ok') continue;
    final detail = DecisionDetail.fromJson(
      jsonDecode(await File('${dir.path}/$id.json').readAsString()),
    );
    await File(
      '${dir.path}/$id.post.txt',
    ).writeAsString(postText(detail, title: status['title']! as String));
    await File('${dir.path}/$id.reply.txt').writeAsString(replyText(detail));
  }
}

/// Étape 1 de la relecture d'une issue modifiée (#122) : pour chaque
/// brouillon non publié, écrit dans [dir] son détail (`<id>.json`), son
/// texte (`<id>.post.txt`), sa réponse en fil (`<id>.reply.txt`, vide s'il
/// n'y en a pas) et sa carte (`<id>.png`, téléchargée), ou, pour
/// un titre écrit à la main, le titre à rendre (`<id>.title.txt`). Écrit
/// `review.json` : `[{"id", "render": bool}]`. Avec [checkedOnly] (publication,
/// #112), seulement les brouillons cochés.
Future<void> planReview({
  required http.Client client,
  required String baseUrl,
  required String body,
  required Directory dir,
  bool checkedOnly = false,
}) async {
  await dir.create(recursive: true);
  final plan = <Map<String, Object?>>[];
  for (final draft in parseDailyIssue(body)) {
    if (draft.postUrl != null) continue;
    if (checkedOnly && !draft.checked) continue;
    final title = draft.title;
    if (title == null) continue;
    final raw = await _get(
      client,
      '$baseUrl/${decisionDetailPath(draft.decisionId)}',
    );
    if (raw == null) continue;
    final id = draft.decisionId;
    await File('${dir.path}/$id.json').writeAsString(raw);
    final detail = DecisionDetail.fromJson(jsonDecode(raw));
    final render = draft.text == null;
    if (render) {
      // Titre écrit à la main : carte et textes à produire.
      await File('${dir.path}/$id.title.txt').writeAsString(title);
      // Un titre trop long pour le post l'est aussi pour la carte : le rendu
      // dira « titre à écrire » et le commentaire demandera de raccourcir.
      String text;
      try {
        text = postText(detail, title: frenchTypography(title));
      } on StateError {
        text = '';
      }
      await File('${dir.path}/$id.post.txt').writeAsString(text);
      await File('${dir.path}/$id.reply.txt').writeAsString(replyText(detail));
    } else {
      await File('${dir.path}/$id.post.txt').writeAsString(draft.text!);
      await File('${dir.path}/$id.reply.txt').writeAsString(draft.reply ?? '');
      final image = draft.imageUrl;
      if (image != null) {
        final response = await client.get(Uri.parse(image));
        if (response.statusCode == 200) {
          await File('${dir.path}/$id.png').writeAsBytes(response.bodyBytes);
        }
      }
    }
    plan.add({'id': id, 'render': render});
  }
  await File('${dir.path}/review.json').writeAsString(jsonEncode(plan));
}

/// Étape 3 de la relecture (#122), après le rendu des cartes et des aperçus :
/// envoie les aperçus dans [store] et écrit le commentaire de relecture :
/// verdict du relecteur (#120) et aperçu par brouillon, plus la carte et les
/// textes produits pour un titre écrit à la main.
Future<String> buildReviewComment({
  required ObjectStore store,
  required String publicBaseUrl,
  required String body,
  required Directory dir,
  required String version,
}) async {
  final day = dailyIssueDay(body) ?? DateTime.now().toUtc();
  final drafts = {for (final d in parseDailyIssue(body)) d.decisionId: d};
  final plan =
      (jsonDecode(await File('${dir.path}/review.json').readAsString()) as List)
          .cast<Map<String, Object?>>();
  final out = StringBuffer()
    ..writeln(reviewCommentMarker)
    ..writeln('### Relecture et aperçus')
    ..writeln()
    ..writeln(
      'Mis à jour après chaque modification de l\'issue. Rien n\'est '
      'publié avant le label `$publishLabel`.',
    );
  for (final item in plan) {
    final id = item['id']! as String;
    final draft = drafts[id]!;
    out
      ..writeln()
      ..writeln('#### ${draft.title}')
      ..writeln();
    final rendered = item['render'] == true;
    final review = await reviewDraft(dir, draft, render: rendered);
    if (review == null) {
      out.writeln('⚠️ $titleTooLong.');
      continue;
    }
    final (:text, :alt, :reply, :problems) = review;
    out.writeln(
      problems.isEmpty
          ? '✅ Relecture OK'
          : '⚠️ Relecture : à corriger avant publication\n'
                '${problems.map((p) => '- $p').join('\n')}',
    );
    final preview = File('${dir.path}/$id-apercu.png');
    if (await preview.exists()) {
      final key = draftPreviewKey(day, id, version: version);
      await store.writeBytes(
        key,
        await preview.readAsBytes(),
        contentType: 'image/png',
      );
      out
        ..writeln()
        ..writeln('<img src="$publicBaseUrl/$key" width="390" alt="Aperçu">');
    }
    if (rendered) {
      out
        ..writeln()
        ..writeln('Texte produit avec ton titre :')
        ..writeln()
        ..writeln('```text\n$text\n```')
        ..writeln()
        ..writeln('Texte alternatif :')
        ..writeln()
        ..writeln('```text\n$alt\n```');
      if (reply != null) {
        out
          ..writeln()
          ..writeln('Réponse en fil :')
          ..writeln()
          ..writeln('```text\n$reply\n```');
      }
    }
  }
  return out.toString();
}

/// Problème d'un titre écrit à la main trop long pour la carte.
const titleTooLong =
    'Ce titre ne tient pas sur la carte, même en petit : raccourcis-le';

/// Relecture d'un brouillon préparé par [planReview] dans [dir] (relecture
/// #122 et publication #112) : texte du post, texte alternatif (produit pour
/// un titre écrit à la main, [render]), réponse en fil (`null` : aucune) et
/// problèmes du relecteur (#120) ; `null` si la carte du titre écrit n'a pas
/// pu être rendue.
Future<({String text, String? alt, String? reply, List<String> problems})?>
reviewDraft(Directory dir, Draft draft, {required bool render}) async {
  final id = draft.decisionId;
  if (render && await _status(dir, id) != 'ok') return null;
  final detail = DecisionDetail.fromJson(
    jsonDecode(await File('${dir.path}/$id.json').readAsString()),
  );
  final text = await File('${dir.path}/$id.post.txt').readAsString();
  final alt = render
      ? altText(detail, title: frenchTypography(draft.title!))
      : draft.alt;
  final replyFile = File('${dir.path}/$id.reply.txt');
  final written = await replyFile.exists()
      ? (await replyFile.readAsString()).trim()
      : '';
  final reply = written.isEmpty ? null : written;
  return (
    text: text,
    alt: alt,
    reply: reply,
    problems: [
      ...proofread(detail, text: text, alt: alt),
      ...proofreadReply(reply),
    ],
  );
}

Future<String?> _status(Directory dir, String id) async {
  final file = File('${dir.path}/$id.png.json');
  if (!await file.exists()) return null;
  return (jsonDecode(await file.readAsString()) as Map)['status'] as String?;
}

Future<String?> _get(http.Client client, String url) async {
  final response = await client.get(Uri.parse(url));
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw HttpException('GET $url : HTTP ${response.statusCode}');
  }
  return utf8.decode(response.bodyBytes);
}
