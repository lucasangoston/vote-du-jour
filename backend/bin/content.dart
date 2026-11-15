// Issue du jour de la content factory (#111), lancée par content.yml.
//
//   dart run bin/content.dart select --base-url <URL publique> \
//     --issues <issues.json> --dir <dossier>
//       Choisit les décisions du jour et écrit leurs détails dans <dossier>.
//       <issues.json> : issues `content` des 7 derniers jours
//       (`gh issue list --json title,body`), pour ne rien reproposer et
//       n'ouvrir qu'une issue par jour.
//       Affiche le nombre de décisions retenues.
//
//   (rendu des cartes : app/tool/social_card/render_social_card_test.dart)
//
//   dart run bin/content.dart texts --base-url <URL> --dir <dossier>
//       Écrit <id>.post.txt et <id>.reply.txt (fil de réponses) pour
//       chaque carte rendue (aperçus, #122).
//
//   (aperçus : app/tool/social_card/render_bluesky_preview_test.dart)
//
//   dart run bin/content.dart issue --base-url <URL publique> \
//     --dir <dossier> --store r2|local [--out <dossier local>]
//       Envoie les cartes rendues et écrit <dossier>/issue.md et
//       <dossier>/issue-title.txt (vides s'il n'y a aucun brouillon).
//       [--history <closed.json>] : issues `content` fermées
//       (`gh issue list --json body`), pour le compteur « 30 sans
//       correction » (#113) affiché en tête, et l'audience des derniers
//       posts publiés.
//
// Relecture d'une issue du jour modifiée (#122), lancée par
// content-review.yml :
//
//   dart run bin/content.dart review-plan --base-url <URL> --dir <dossier> \
//     --body <corps de l'issue>
//       Prépare détails, textes et cartes ; écrit <dossier>/review.json.
//
//   (cartes des titres écrits à la main, puis aperçus)
//
//   dart run bin/content.dart review-comment --base-url <URL> \
//     --dir <dossier> --body <corps> --version <n> --store r2|local
//       Envoie les aperçus, écrit <dossier>/review.md.
//
// Publication sur Bluesky au label `publier` (#112), lancée par
// content-publish.yml :
//
//   dart run bin/content.dart publish-plan --base-url <URL> --dir <dossier> \
//     --body <corps de l'issue>
//       Comme review-plan, pour les seuls brouillons cochés.
//
//   (cartes des titres écrits à la main)
//
//   GITHUB_TOKEN=… BLUESKY_HANDLE=… BLUESKY_APP_PASSWORD=… \
//   dart run bin/content.dart publish --base-url <URL> --dir <dossier> \
//     --repo <propriétaire/dépôt> --issue <n>
//       Publie les brouillons cochés, écrit le lien de chaque post dans
//       l'issue, puis <dossier>/publish.md (commentaire) et
//       <dossier>/publish.json ({"done": bool} : issue à fermer).
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:vote_job/vote_job.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('base-url', mandatory: true, help: 'URL publique du bucket.')
    ..addOption('dir', mandatory: true, help: 'Dossier de travail.')
    ..addOption('issues', help: 'Issues `content` récentes (JSON de gh).')
    ..addOption('history', help: 'Issues `content` fermées (JSON de gh).')
    ..addOption('store', allowed: ['local', 'r2'], defaultsTo: 'local')
    ..addOption('out', defaultsTo: 'build/publish', help: 'Store local.')
    ..addOption('body', help: 'Corps de l\'issue du jour (fichier).')
    ..addOption('version', help: 'Version des aperçus (cache des images).')
    ..addOption('repo', help: 'Dépôt GitHub de l\'issue du jour.')
    ..addOption('issue', help: 'Numéro de l\'issue du jour.');
  const commands = [
    'select',
    'texts',
    'issue',
    'review-plan',
    'review-comment',
    'publish-plan',
    'publish',
  ];
  if (arguments.isEmpty || !commands.contains(arguments.first)) {
    stderr.writeln(
      'Usage : content.dart ${commands.join('|')} …\n${parser.usage}',
    );
    exit(64);
  }
  final args = parser.parse(arguments.skip(1).toList());
  final baseUrl = (args['base-url'] as String).replaceAll(RegExp(r'/+$'), '');
  final dir = Directory(args['dir'] as String);
  final now = DateTime.now().toUtc();

  switch (arguments.first) {
    case 'select':
      final issuesPath = args['issues'] as String?;
      final issues = issuesPath == null
          ? const <Map<Object?, Object?>>[]
          : [
              for (final i
                  in jsonDecode(File(issuesPath).readAsStringSync()) as List)
                if (i is Map) i,
            ];
      final today = dailyIssueTitle(parisDay(now));
      var selected = const <SelectedDecision>[];
      if (issues.any((i) => i['title'] == today)) {
        stdout.writeln('issue « $today » déjà ouverte');
      } else {
        final client = http.Client();
        try {
          selected = await selectDailyDrafts(
            client: client,
            baseUrl: baseUrl,
            handled: handledDecisionIds([
              for (final i in issues)
                if (i['body'] is String) i['body']! as String,
            ]),
            now: now,
            dir: dir,
          );
        } finally {
          client.close();
        }
      }
      if (selected.isEmpty) {
        dir.createSync(recursive: true);
        File('${dir.path}/selection.json').writeAsStringSync('[]');
      }
      for (final s in selected) {
        stdout.writeln('${s.id}  ${s.title ?? '(titre à écrire)'}');
      }
      stdout.writeln('${selected.length} décision(s) retenue(s)');
    case 'issue':
      final store = args['store'] == 'r2'
          ? r2StoreFromEnvironment()
          : LocalDirectoryStore(args['out'] as String);
      final day = parisDay(now);
      final history = switch (args['history'] as String?) {
        null => null,
        final path => [
          for (final i in jsonDecode(File(path).readAsStringSync()) as List)
            if (i is Map && i['body'] is String) i['body']! as String,
        ],
      };
      // L'audience est un rappel : une panne de Bluesky n'empêche pas
      // l'issue du jour.
      var stats = const <PostStats>[];
      if (history != null) {
        final client = http.Client();
        try {
          stats = await fetchPostStats(client: client, bodies: history);
        } on Exception catch (e) {
          stderr.writeln('audience des posts indisponible : $e');
        } finally {
          client.close();
        }
      }
      final body = await buildDailyIssue(
        store: store,
        publicBaseUrl: baseUrl,
        parisDay: day,
        dir: dir,
        streak: history == null ? null : uncorrectedStreak(history),
        stats: stats,
      );
      File('${dir.path}/issue.md').writeAsStringSync(body);
      File(
        '${dir.path}/issue-title.txt',
      ).writeAsStringSync(body.isEmpty ? '' : dailyIssueTitle(day));
      stdout.writeln(body.isEmpty ? 'aucun brouillon' : dailyIssueTitle(day));
    case 'texts':
      await writeDraftTexts(dir);
    case 'review-plan' || 'publish-plan':
      final client = http.Client();
      try {
        await planReview(
          client: client,
          baseUrl: baseUrl,
          body: File(args['body'] as String).readAsStringSync(),
          dir: dir,
          checkedOnly: arguments.first == 'publish-plan',
        );
      } finally {
        client.close();
      }
      stdout.writeln(File('${dir.path}/review.json').readAsStringSync());
    case 'review-comment':
      final store = args['store'] == 'r2'
          ? r2StoreFromEnvironment()
          : LocalDirectoryStore(args['out'] as String);
      final comment = await buildReviewComment(
        store: store,
        publicBaseUrl: baseUrl,
        body: File(args['body'] as String).readAsStringSync(),
        dir: dir,
        version:
            (args['version'] as String?) ?? '${now.millisecondsSinceEpoch}',
      );
      File('${dir.path}/review.md').writeAsStringSync(comment);
    case 'publish':
      final env = Platform.environment;
      final client = http.Client();
      try {
        final report = await publishDrafts(
          bluesky: BlueskyClient(
            client: client,
            handle: env['BLUESKY_HANDLE']!,
            appPassword: env['BLUESKY_APP_PASSWORD']!,
          ),
          issue: GitHubIssueBody(
            client: client,
            repository: args['repo'] as String,
            number: int.parse(args['issue'] as String),
            token: env['GITHUB_TOKEN']!,
          ),
          dir: dir,
        );
        File(
          '${dir.path}/publish.md',
        ).writeAsStringSync(publishComment(report));
        File(
          '${dir.path}/publish.json',
        ).writeAsStringSync(jsonEncode({'done': report.done}));
        for (final p in report.published) {
          stdout.writeln('publié  ${p.id}  ${p.url}');
        }
        for (final b in report.blocked) {
          stdout.writeln('bloqué  ${b.id}  ${b.problems.join(' ; ')}');
        }
      } finally {
        client.close();
      }
  }
}
