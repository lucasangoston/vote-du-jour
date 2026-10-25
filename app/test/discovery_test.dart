import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/decisions_repository.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    final client = MockClient((_) async => http.Response('', 503));
    await tester.pumpWidget(
      VoteDuJourApp(
        repository: DecisionsRepository(
          baseUrl: 'https://example.test',
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la liste ouvre « Ajouter le widget »', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Ajouter le widget'));
    await tester.pumpAndSettle();

    expect(find.text('Widgets.'), findsOneWidget);

    await tester.tap(find.text('iPhone'));
    await tester.pumpAndSettle();

    expect(find.text('Touchez Modifier › Ajouter un widget.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('la liste ouvre « À propos »', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('À propos'));
    await tester.pumpAndSettle();

    expect(find.text('Le Perchoir'), findsOneWidget);
    expect(find.text('Données de l\u2019Assemblée nationale'), findsOneWidget);
    final footer = find.text(
      'Résumés écrits par une IA. Seul le texte officiel fait foi. '
      'Application non officielle.',
    );
    await tester.scrollUntilVisible(footer, 200);
    expect(footer, findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Confidentialité'), findsOneWidget);
  });
}
