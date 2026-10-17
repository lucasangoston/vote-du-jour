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
    ..addFlag(
      'force',
      help: "Retraite le jeu de données même s'il n'a pas changé.",
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
  final dumpFile = args.option('dump-file');
  final source = dumpFile != null
      ? FileDumpSource(dumpFile)
      : HttpDumpSource(url: args.option('dump-url')!);

  final outcome = await runJob(
    source: source,
    store: store,
    force: args.flag('force'),
  );
  stdout.writeln(outcome);
  // Le client HTTP par défaut garde des connexions ouvertes.
  exit(0);
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
