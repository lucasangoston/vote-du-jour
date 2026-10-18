import 'dart:io';

import 'package:args/args.dart';
import 'package:vote_job/vote_job.dart';

const _r2Env = [
  'R2_ACCOUNT_ID',
  'R2_BUCKET',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
];

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'store',
      allowed: ['local', 'r2'],
      defaultsTo: 'local',
      help:
          'Destination : dossier local (--out) ou bucket R2 '
          '(variables ${_r2Env.join(', ')}).',
    )
    ..addOption(
      'out',
      defaultsTo: 'build/publish',
      help: 'Dossier du mode local.',
    )
    ..addOption(
      'dump-url',
      defaultsTo: scrutinsDumpUrl,
      help: 'URL du jeu de données.',
    )
    ..addOption(
      'dump-file',
      help: 'Lit le jeu de données depuis un fichier zip local.',
    )
    ..addOption(
      'dossiers-url',
      defaultsTo: dossiersDumpUrl,
      help: 'URL du jeu de données des dossiers législatifs.',
    )
    ..addOption(
      'dossiers-file',
      help: 'Lit les dossiers législatifs depuis un fichier zip local.',
    )
    ..addOption(
      'organes-url',
      defaultsTo: organesDumpUrl,
      help: 'URL du jeu de données des acteurs et organes (noms des groupes).',
    )
    ..addOption(
      'organes-file',
      help: 'Lit les acteurs et organes depuis un fichier zip local.',
    )
    ..addFlag(
      'live',
      negatable: false,
      help:
          "Détection en direct : lit la liste des scrutins du site de "
          "l'Assemblée et publie les décisions provisoires (sans télécharger "
          'le jeu de données).',
    )
    ..addOption(
      'live-days',
      defaultsTo: '1-5',
      help: 'Jours de la détection en direct (1 = lundi), heure de Paris.',
    )
    ..addOption(
      'live-hours',
      defaultsTo: '9-24',
      help: 'Heures de la détection en direct, heure de Paris.',
    )
    ..addFlag(
      'ignore-window',
      negatable: false,
      help: 'Détection en direct même hors des jours et heures prévus.',
    )
    ..addOption(
      'site-list-url',
      defaultsTo: siteListUrl,
      help: 'Page de liste des scrutins lue par la détection en direct.',
    )
    ..addFlag(
      'force',
      help: "Retraite les jeux de données même s'ils n'ont pas changé.",
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(64);
  }
  if (args.flag('help')) {
    stdout.writeln(
      'Usage : dart run bin/vote_job.dart [options]\n\n${parser.usage}',
    );
    return;
  }

  final store = switch (args.option('store')) {
    'r2' => _r2StoreFromEnvironment(),
    _ => LocalDirectoryStore(args.option('out')!),
  };
  if (args.flag('live')) {
    await _runLive(args, store);
    // Le client HTTP par défaut garde des connexions ouvertes.
    exit(0);
  }

  final dumpFile = args.option('dump-file');
  final source = dumpFile != null
      ? FileDumpSource(dumpFile)
      : HttpDumpSource(url: args.option('dump-url')!);
  final dossiersFile = args.option('dossiers-file');
  final dossiers = dossiersFile != null
      ? FileDumpSource(dossiersFile)
      : HttpDumpSource(url: args.option('dossiers-url')!);
  final organesFile = args.option('organes-file');
  final organes = organesFile != null
      ? FileDumpSource(organesFile)
      : HttpDumpSource(url: args.option('organes-url')!);

  final outcome = await runJob(
    source: source,
    store: store,
    dossiers: dossiers,
    organes: organes,
    force: args.flag('force'),
  );
  stdout.writeln(outcome);
  // Le client HTTP par défaut garde des connexions ouvertes.
  exit(0);
}

/// Détection en direct. Une erreur de lecture du site est journalisée (en
/// avertissement dans GitHub Actions) sans faire échouer l'exécution.
Future<void> _runLive(ArgResults args, ObjectStore store) async {
  final LiveWindow window;
  try {
    window = LiveWindow.parse(
      days: args.option('live-days')!,
      hours: args.option('live-hours')!,
    );
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
  if (!args.flag('ignore-window') && !window.contains(DateTime.now())) {
    stdout.writeln(LiveOutsideWindow(window));
    return;
  }
  final outcome = await runLivePass(
    site: HttpSiteSource(listUrl: args.option('site-list-url')!),
    store: store,
  );
  stdout.writeln(outcome);
  if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
    for (final w in [
      if (outcome is LiveFailed) 'Site illisible : ${outcome.error}',
      ...outcome.warnings,
    ]) {
      stdout.writeln('::warning title=Détection en direct::$w');
    }
  }
}

R2Store _r2StoreFromEnvironment() {
  final env = Platform.environment;
  final missing = [
    for (final name in _r2Env)
      if ((env[name] ?? '').isEmpty) name,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln(
      'Variables manquantes pour --store=r2 : ${missing.join(', ')}',
    );
    exit(64);
  }
  return R2Store(
    accountId: env['R2_ACCOUNT_ID']!,
    bucket: env['R2_BUCKET']!,
    accessKeyId: env['R2_ACCESS_KEY_ID']!,
    secretAccessKey: env['R2_SECRET_ACCESS_KEY']!,
  );
}
