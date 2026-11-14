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
//   dart run bin/content.dart issue --base-url <URL publique> \
//     --dir <dossier> --store r2|local [--out <dossier local>]
//       Envoie les cartes rendues et écrit <dossier>/issue.md et
//       <dossier>/issue-title.txt (vides s'il n'y a aucun brouillon).
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
    ..addOption('store', allowed: ['local', 'r2'], defaultsTo: 'local')
    ..addOption('out', defaultsTo: 'build/publish', help: 'Store local.');
  if (arguments.isEmpty || !['select', 'issue'].contains(arguments.first)) {
    stderr.writeln('Usage : content.dart select|issue …\n${parser.usage}');
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
      final body = await buildDailyIssue(
        store: store,
        publicBaseUrl: baseUrl,
        parisDay: day,
        dir: dir,
      );
      File('${dir.path}/issue.md').writeAsStringSync(body);
      File(
        '${dir.path}/issue-title.txt',
      ).writeAsStringSync(body.isEmpty ? '' : dailyIssueTitle(day));
      stdout.writeln(body.isEmpty ? 'aucun brouillon' : dailyIssueTitle(day));
  }
}
