import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vote_contract/vote_contract.dart';

import 'bluesky.dart';
import 'daily_issue.dart';
import 'post_text.dart';
import 'proofreader.dart';

/// Corps de l'issue du jour, relu avant chaque écriture : une modification
/// faite pendant la publication n'est pas écrasée.
abstract interface class IssueBody {
  Future<String> read();
  Future<void> write(String body);
}

/// [IssueBody] par l'API REST de GitHub.
class GitHubIssueBody implements IssueBody {
  GitHubIssueBody({
    required http.Client client,
    required this.repository,
    required this.number,
    required String token,
    this.api = 'https://api.github.com',
  }) : _client = client,
       _token = token;

  final http.Client _client;
  final String _token;

  /// `propriétaire/dépôt`.
  final String repository;
  final int number;
  final String api;

  Uri get _uri => Uri.parse('$api/repos/$repository/issues/$number');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  @override
  Future<String> read() async {
    final response = await _client.get(_uri, headers: _headers);
    _check(response, 'GET');
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['body']
            as String? ??
        '';
  }

  @override
  Future<void> write(String body) async {
    final response = await _client.patch(
      _uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'body': body}),
    );
    _check(response, 'PATCH');
  }

  void _check(http.Response response, String method) {
    if (response.statusCode != 200) {
      throw HttpException(
        '$method issue #$number : HTTP ${response.statusCode}',
      );
    }
  }
}

/// Un brouillon coché que la publication n'a pas pu publier, et pourquoi.
typedef BlockedDraft = ({String id, String title, List<String> problems});

/// Un brouillon coché publié, par ce passage ou un précédent.
typedef PublishedDraft = ({String id, String title, String url});

/// Résultat d'une publication : [done] quand chaque brouillon coché (au
/// moins un) est publié ; l'issue peut alors être fermée.
typedef PublishReport = ({
  List<PublishedDraft> published,
  List<BlockedDraft> blocked,
  bool done,
});

/// Étape 3 de la publication (#112), après `planReview(checkedOnly: true)`
/// et le rendu des cartes des titres écrits à la main : publie sur Bluesky
/// chaque brouillon coché, avec son texte tel qu'édité, relu (#120). Un
/// brouillon en échec n'est pas publié. Le lien de chaque post est écrit
/// dans son bloc aussitôt publié ; un bloc qui porte un lien n'est jamais
/// republié, et un post déjà en ligne avec le même texte est retrouvé au lieu
/// d'être republié : relancer est sans risque.
Future<PublishReport> publishDrafts({
  required BlueskyClient bluesky,
  required IssueBody issue,
  required Directory dir,
  DateTime? now,
}) async {
  final body = await issue.read();
  final planFile = File('${dir.path}/review.json');
  final plan = {
    if (await planFile.exists())
      for (final item in jsonDecode(await planFile.readAsString()) as List)
        (item as Map)['id'] as String: item['render'] == true,
  };
  final published = <PublishedDraft>[];
  final blocked = <BlockedDraft>[];
  var checked = 0;
  for (final draft in parseDailyIssue(body)) {
    if (!draft.checked) continue;
    checked++;
    final id = draft.decisionId;
    final title = draft.title;
    if (draft.postUrl != null) {
      published.add((id: id, title: title ?? id, url: draft.postUrl!));
      continue;
    }
    void block(List<String> problems) => blocked.add((
      id: id,
      title: title ?? 'Titre à écrire',
      problems: problems,
    ));
    if (title == null) {
      block(['titre à écrire : le champ titre est vide']);
      continue;
    }
    final render = plan[id];
    if (render == null) {
      block(['détail de la décision introuvable']);
      continue;
    }
    if (render && await _status(dir, id) != 'ok') {
      block([
        'ce titre ne tient pas sur la carte, même en petit : raccourcis-le',
      ]);
      continue;
    }
    final detail = DecisionDetail.fromJson(
      jsonDecode(await File('${dir.path}/$id.json').readAsString()),
    );
    final text = await File('${dir.path}/$id.post.txt').readAsString();
    final alt = render
        ? altText(detail, title: frenchTypography(title))
        : draft.alt;
    final problems = proofread(detail, text: text, alt: alt);
    final card = File('${dir.path}/$id.png');
    final image = await card.exists() ? await card.readAsBytes() : null;
    if (image == null) {
      problems.add('carte introuvable');
    } else if (image.length > blueskyImageMaxBytes) {
      problems.add(
        'carte de ${image.length} octets, $blueskyImageMaxBytes au plus',
      );
    }
    if (problems.isNotEmpty) {
      block(problems);
      continue;
    }
    final (width, height) = pngSize(image!);
    final url =
        await bluesky.findPost(text) ??
        await bluesky.post(
          text: text,
          image: image,
          alt: alt!,
          width: width,
          height: height,
          now: now,
        );
    await issue.write(markPublished(await issue.read(), id, url));
    published.add((id: id, title: title, url: url));
  }
  return (
    published: published,
    blocked: blocked,
    done: checked > 0 && blocked.isEmpty,
  );
}

/// Commentaire laissé sur l'issue après une publication.
String publishComment(PublishReport report) {
  final out = StringBuffer();
  if (report.done) {
    out.writeln('Publié sur Bluesky :');
  } else if (report.published.isEmpty && report.blocked.isEmpty) {
    return 'Aucun post coché : rien n\'est publié. Coche les posts à publier, '
        'puis repose le label `$publishLabel`.\n';
  } else {
    out
      ..writeln(
        '⚠️ Publication incomplète : corrige les posts ci-dessous, puis '
        'repose le label `$publishLabel`. Les posts déjà publiés ne le '
        'seront pas deux fois.',
      )
      ..writeln();
    if (report.published.isNotEmpty) out.writeln('Publiés :');
  }
  for (final p in report.published) {
    out.writeln('- [${p.title}](${p.url})');
  }
  if (report.blocked.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Non publiés :');
    for (final b in report.blocked) {
      out.writeln('- ${b.title}');
      for (final p in b.problems) {
        out.writeln('  - $p');
      }
    }
  }
  return out.toString();
}

/// Largeur et hauteur d'une image PNG, lues dans son en-tête IHDR.
(int, int) pngSize(List<int> png) {
  if (png.length < 24) throw const FormatException('PNG trop court');
  int at(int i) =>
      (png[i] << 24) | (png[i + 1] << 16) | (png[i + 2] << 8) | png[i + 3];
  return (at(16), at(20));
}

Future<String?> _status(Directory dir, String id) async {
  final file = File('${dir.path}/$id.png.json');
  if (!await file.exists()) return null;
  return (jsonDecode(await file.readAsString()) as Map)['status'] as String?;
}
