import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

/// Écart toléré entre une capture et sa référence, sur macOS où elles sont
/// produites.
const _goldenTolerance = 0.005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  // Les captures de référence viennent de macOS : sur Linux (CI), le rendu du
  // texte et l'anticrénelage s'écartent de près de 3 %, au-delà de toute
  // tolérance utile. La CI vérifie la mise en page par les tests widget ; les
  // captures se comparent en local, sur macOS.
  if (!Platform.isMacOS) {
    goldenFileComparator = _SkippedComparator();
  } else if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(comparator.basedir);
  }
  await testMain();
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(Uri basedir) : super(basedir.resolve('_'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _goldenTolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

class _SkippedComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}
