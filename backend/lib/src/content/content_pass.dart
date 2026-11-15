import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

import '../live/paris_time.dart';
import '../object_store.dart';
import 'content_selection.dart';
import 'content_stats.dart';
import 'daily_issue.dart';
import 'post_text.dart';
import 'proofreader.dart';

/// Heure de Paris avant laquelle l'issue du jour n'est pas ouverte : le jeu
/// de données des scrutins arrive vers 12 h 30 (#111).
const dailyIssueNotBefore = 13;

/// Une décision retenue, prête à rendre : son détail est écrit dans
/// `<dir>/<id>.json`, la carte sera rendue dans `<dir>/<id>.png`.
typedef SelectedDecision = ({String id, String? title});

/// Étape 1 de l'issue du jour (#111) : lit le contrat publié sous [baseUrl],
/// choisit les décisions du jour ([selectPostDecisions]) et écrit leurs
/// détails dans [dir], avec `selection.json`. Rien avant
/// [dailyIssueNotBefore] h (Paris).
Future<List<SelectedDecision>> selectDailyDrafts({
  required http.Client client,
  required String baseUrl,
  required Set<String> handled,
  required DateTime now,
  required Directory dir,
}) async {
  if (toParis(now).hour < dailyIssueNotBefore) return const [];
  final index = DecisionIndex.fromJson(
    jsonDecode(await _get(client, '$baseUrl/$indexPath')),
  );
  final oldest = now.subtract(postMaxAge);
  final details = <String, DecisionDetail>{};
  for (final d in index.decisions) {
    if (d.date.isBefore(oldest) || handled.contains(d.id)) continue;
    if (d.status != DecisionStatus.confirmee) continue;
    final raw = await _getOrNull(
      client,
      '$baseUrl/${decisionDetailPath(d.id)}',
    );
    if (raw == null) continue;
    details[d.id] = DecisionDetail.fromJson(jsonDecode(raw)).withDecision(d);
  }
  final selected = selectPostDecisions(
    index: index,
    details: details,
    handled: handled,
    now: now,
  );
  await dir.create(recursive: true);
  final result = <SelectedDecision>[];
  for (final detail in selected) {
    final id = detail.decision.id;
    await File(
      '${dir.path}/$id.json',
    ).writeAsString(jsonEncode(detail.toJson()));
    final summary = detail.decision.summary;
    result.add((id: id, title: summary?.shortTitle ?? summary?.title));
  }
  await File(
    '${dir.path}/selection.json',
  ).writeAsString(jsonEncode([for (final s in result) s.id]));
  return result;
}

/// Étape 3 de l'issue du jour (#111), après le rendu des cartes : envoie
/// chaque carte rendue dans [store] (`content/<jour>/<id>.png`) et écrit le
/// corps de l'issue. Une carte « titre à écrire » n'a ni image ni texte.
Future<String> buildDailyIssue({
  required ObjectStore store,
  required String publicBaseUrl,
  required DateTime parisDay,
  required Directory dir,
  int? streak,
  List<PostStats> stats = const [],
}) async {
  final ids =
      (jsonDecode(await File('${dir.path}/selection.json').readAsString())
              as List)
          .cast<String>();
  final drafts = <Draft>[];
  for (final id in ids) {
    final detail = DecisionDetail.fromJson(
      jsonDecode(await File('${dir.path}/$id.json').readAsString()),
    );
    final status =
        jsonDecode(await File('${dir.path}/$id.png.json').readAsString())
            as Map<String, Object?>;
    switch (status['status']) {
      case 'ok':
        final title = status['title']! as String;
        final key = draftImageKey(parisDay, id);
        await store.writeBytes(
          key,
          await File('${dir.path}/$id.png').readAsBytes(),
          contentType: 'image/png',
        );
        final text = postText(detail, title: title);
        final alt = altText(detail, title: title);
        final reply = replyText(detail);
        final preview = File('${dir.path}/$id-apercu.png');
        String? previewUrl;
        if (await preview.exists()) {
          final previewKey = draftPreviewKey(parisDay, id);
          await store.writeBytes(
            previewKey,
            await preview.readAsBytes(),
            contentType: 'image/png',
          );
          previewUrl = '$publicBaseUrl/$previewKey';
        }
        drafts.add(
          Draft(
            decisionId: id,
            sourceUrl: detail.decision.sourceUrl,
            title: title,
            text: text,
            alt: alt,
            reply: reply,
            imageUrl: '$publicBaseUrl/$key',
            previewUrl: previewUrl,
            problems: [
              ...proofread(detail, text: text, alt: alt),
              ...proofreadReply(reply),
            ],
          ),
        );
      case 'titre_a_ecrire':
        drafts.add(
          Draft(
            decisionId: id,
            sourceUrl: detail.decision.sourceUrl,
            title: null,
          ),
        );
      default:
      // pas_de_carte : la sélection l'exclut déjà ; rien à proposer.
    }
  }
  return drafts.isEmpty
      ? ''
      : renderDailyIssue(parisDay, drafts, streak: streak, stats: stats);
}

Future<String> _get(http.Client client, String url) async {
  final body = await _getOrNull(client, url);
  if (body == null) throw HttpException('GET $url : introuvable');
  return body;
}

Future<String?> _getOrNull(http.Client client, String url) async {
  final response = await client.get(Uri.parse(url));
  if (response.statusCode == 404) return null;
  if (response.statusCode != 200) {
    throw HttpException('GET $url : HTTP ${response.statusCode}');
  }
  return utf8.decode(response.bodyBytes);
}
