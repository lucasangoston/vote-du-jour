import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/decisions_repository.dart';

void main() {
  testWidgets(
    'affiche le titre court et l\'étape, et lit encore un index sans ces champs',
    (tester) async {
      final client = MockClient((request) async {
        final json = {
          'schemaVersion': 1,
          'generatedAt': '2026-10-17T10:00:00.000Z',
          'decisions': [
            // Texte adopté à main levée (ticket #8) : ni numéro ni décompte.
            {
              'id': 'L17-VD234087DEC',
              'voteMode': 'main_levee',
              'type': 'ensemble',
              'status': 'confirmee',
              'result': 'adopte',
              'date': '2026-10-07',
              'officialTitle':
                  "projet de loi autorisant l'approbation de l'accord "
                  'multilatéral GloBE',
              'sourceUrl':
                  'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N54379',
              'shortTitle': 'Accord multilatéral GloBE',
              'stage': "1re lecture à l'AN",
            },
            {
              'id': 'VTANR5L17V1194',
              'numero': 1194,
              'type': 'ensemble',
              'status': 'confirmee',
              'result': 'adopte',
              'date': '2025-04-01',
              'officialTitle':
                  "l'ensemble de la proposition de loi visant à sortir la "
                  'France du piège du narcotrafic (première lecture).',
              'sourceUrl':
                  'https://www.assemblee-nationale.fr/dyn/17/scrutins/1194',
              'shortTitle': 'Sortir la France du piège du narcotrafic',
              'stage': "1re lecture à l'AN",
              'dossierUrl':
                  'https://www.assemblee-nationale.fr/dyn/17/dossiers/DLR5L17N50169',
            },
            {
              'id': 'VTANR5L17V1018',
              'numero': 1018,
              'type': 'resolution',
              'status': 'confirmee',
              'result': 'adopte',
              'date': '2025-03-13',
              'officialTitle': 'la proposition de résolution exemple.',
              'sourceUrl':
                  'https://www.assemblee-nationale.fr/dyn/17/scrutins/1018',
              'shortTitle': 'Les effets psychologiques de TikTok',
              'stage': 'Résolution (sans valeur de loi)',
            },
            // Format publié avant le ticket #7 : ni titre court ni étape.
            {
              'id': 'VTANR5L17V217',
              'numero': 217,
              'type': 'ensemble',
              'status': 'confirmee',
              'result': 'rejete',
              'date': '2024-10-31',
              'officialTitle': "l'ensemble d'un ancien index.",
              'sourceUrl':
                  'https://www.assemblee-nationale.fr/dyn/17/scrutins/217',
            },
          ],
        };
        return http.Response.bytes(utf8.encode(jsonEncode(json)), 200);
      });

      await tester.pumpWidget(
        VoteDuJourApp(
          repository: DecisionsRepository(
            baseUrl: 'https://example.test',
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sortir la France du piège du narcotrafic'),
        findsOneWidget,
      );
      expect(find.textContaining('narcotrafic (première'), findsNothing);
      expect(find.text("1re lecture à l'AN"), findsNWidgets(2));
      expect(find.text('Accord multilatéral GloBE'), findsOneWidget);
      expect(
        find.text('à main levée'),
        findsOneWidget,
        reason: 'seule la décision à main levée porte la mention',
      );
      expect(find.text('Adopté'), findsNWidgets(3));
      expect(find.text('Résolution (sans valeur de loi)'), findsOneWidget);
      expect(find.text("L'ensemble d'un ancien index."), findsOneWidget);
      expect(find.textContaining('loi votée'), findsNothing);
    },
  );
}
