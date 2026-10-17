import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

import 'fixtures.dart';

void main() {
  group('readScrutinsArchive sur de vrais scrutins', () {
    late Map<int, Scrutin> byNumero;

    setUpAll(() {
      final scrutins = readScrutinsArchive(fixtureArchive());
      byNumero = {for (final s in scrutins) s.numero: s};
    });

    test('lit chaque fichier JSON de l\'archive', () {
      expect(byNumero.keys, unorderedEquals(fixtureNumeros));
    });

    test('motion de censure adoptée (scrutin 519)', () {
      final s = byNumero[519]!;
      expect(s.uid, 'VTANR5L17V519');
      expect(s.date, DateTime.utc(2024, 12, 4));
      expect(s.codeTypeVote, 'MOC');
      expect(s.libelleTypeVote, 'motion de censure');
      expect(s.result, VoteResult.adopte);
      expect(
        s.titre,
        startsWith('la motion de censure déposée en application'),
      );
      expect(s.decompte.pour, 331);
      expect(s.decompte.contre, 0);
      expect(s.decompte.abstentions, 0);
      expect(s.decompte.nonVotants, 1);
      expect(s.dossierRef, isNull);
    });

    test('vote sur l\'ensemble rejeté (scrutin 217)', () {
      final s = byNumero[217]!;
      expect(s.date, DateTime.utc(2024, 10, 31));
      expect(s.libelleTypeVote, 'scrutin public ordinaire');
      expect(s.result, VoteResult.rejete);
      expect(s.decompte.pour, 119);
      expect(s.decompte.contre, 197);
      expect(s.decompte.abstentions, 18);
    });

    test('conserve les apostrophes typographiques du titre (scrutin 2278)', () {
      expect(
        byNumero[2278]!.titre,
        'l’ensemble de la proposition de loi sur la profession d’infirmier '
        '(texte de la commission mixte paritaire).',
      );
    });

    test('lit la référence du dossier législatif (scrutin 7349)', () {
      expect(byNumero[7349]!.dossierRef, 'DLR5L17N52700');
    });

    test('lit le vote de chaque groupe (scrutin 4802)', () {
      final s = byNumero[4802]!;
      expect(s.codeTypeVote, 'SPS');
      expect(s.libelleTypeVote, 'scrutin public solennel');
      expect(s.groupVotes, hasLength(12));
      final first = s.groupVotes.first;
      expect(first.organeRef, 'PO845401');
      expect(first.positionMajoritaire, 'pour');
      expect(first.decompte.pour, 95);
      expect(first.decompte.contre, 0);
      // La somme des groupes ne dépasse pas le décompte total.
      final pour = s.groupVotes.fold(0, (sum, g) => sum + g.decompte.pour);
      expect(pour, lessThanOrEqualTo(s.decompte.pour));
    });

    test('ignore les fichiers qui ne sont pas des scrutins JSON', () {
      final archive = Archive()
        ..addFile(ArchiveFile.string('LISEZMOI.txt', 'pas un scrutin'))
        ..addFile(
          ArchiveFile.bytes(
            'json/VTANR5L17V519.json',
            fixtureFile(519).readAsBytesSync(),
          ),
        );
      final scrutins = readScrutinsArchive(ZipEncoder().encodeBytes(archive));
      expect(scrutins.map((s) => s.numero), [519]);
    });
  });

  group('format inattendu', () {
    test('signale le fichier et le champ en cause', () {
      final json = jsonDecode(fixtureFile(519).readAsStringSync()) as Map;
      (json['scrutin']['sort'] as Map)['code'] = 'reporté';
      expect(
        () => parseScrutinJson(jsonEncode(json), source: 'VTANR5L17V519.json'),
        throwsA(
          isA<DumpFormatException>()
              .having((e) => e.source, 'source', 'VTANR5L17V519.json')
              .having((e) => e.message, 'message', contains('sort.code')),
        ),
      );
    });

    test('refuse un JSON invalide', () {
      expect(
        () => parseScrutinJson('{"scrutin": ', source: 'x.json'),
        throwsA(isA<DumpFormatException>()),
      );
    });
  });
}
