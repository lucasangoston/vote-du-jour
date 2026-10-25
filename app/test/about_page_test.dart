import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:votedujour/main.dart';
import 'package:votedujour/src/about_page.dart';
import 'package:votedujour/src/add_widget_page.dart';
import 'package:votedujour/src/appearance.dart';
import 'package:votedujour/src/decisions_repository.dart';
import 'package:votedujour/src/notifications/important_votes_notifications.dart';
import 'package:votedujour/src/notifications/push_messaging.dart';
import 'package:votedujour/src/theme.dart';

/// Messagerie accordée, sans notification : la ligne du réglage s'affiche
/// activée.
class _GrantedMessaging implements PushMessaging {
  @override
  Future<PushPermission> permission() async => PushPermission.granted;

  @override
  Future<PushPermission> requestPermission() async => PushPermission.granted;

  @override
  Future<void> subscribe(String topic) async {}

  @override
  Future<void> unsubscribe(String topic) async {}

  @override
  Future<PushNotification?> initialNotification() async => null;

  @override
  Stream<PushNotification> get opened => const Stream.empty();

  @override
  Stream<PushNotification> get foreground => const Stream.empty();
}

/// Page À propos seule, dans le thème [brightness], à la taille d'un iPhone.
Future<void> _pumpAbout(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  AppearanceSettings? appearance,
  bool withNotifications = false,
}) async {
  ImportantVotesNotifications? notifications;
  if (withNotifications) {
    notifications = ImportantVotesNotifications(messaging: _GrantedMessaging());
    await tester.runAsync(notifications.start);
  }
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      builder: (context, child) => notifications == null
          ? child!
          : NotificationsScope(notifier: notifications, child: child!),
      home: AppearanceScope(
        notifier:
            appearance ??
            AppearanceSettings(
              mode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
            ),
        child: const AboutPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// L'app complète, sans données (la liste affiche son erreur).
Future<void> _pumpApp(
  WidgetTester tester,
  AppearanceSettings appearance,
) async {
  await tester.pumpWidget(
    VoteDuJourApp(
      repository: DecisionsRepository(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => http.Response('', 503)),
      ),
      appearance: appearance,
    ),
  );
  await tester.pumpAndSettle();
}

Brightness _brightnessOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('contenu réduit de la maquette', (tester) async {
    await _pumpAbout(tester);

    expect(find.text('Le Perchoir'), findsOneWidget);
    for (final label in ['Auto', 'Jour', 'Nuit']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ajouter le widget'), findsOneWidget);
    for (final label in ['Pour', 'Contre', 'Abstention']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Données de l’Assemblée nationale'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Confidentialité'), findsOneWidget);
    expect(
      find.text(
        'Résumés écrits par une IA. Seul le texte officiel fait foi. '
        'Application non officielle.',
      ),
      findsOneWidget,
    );
    // Les anciennes sections ont disparu.
    expect(find.text('Source des données'), findsNothing);
  });

  testWidgets('« Ajouter le widget » ouvre la page du widget', (tester) async {
    await _pumpAbout(tester);
    await tester.tap(find.text('Ajouter le widget'));
    await tester.pumpAndSettle();
    expect(find.byType(AddWidgetPage), findsOneWidget);
  });

  group('apparence', () {
    testWidgets('Auto par défaut : suit le téléphone', (tester) async {
      final appearance = await AppearanceSettings.load();
      expect(appearance.mode, ThemeMode.system);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(tester, appearance);
      expect(_brightnessOf(tester), Brightness.dark);
    });

    testWidgets('le choix change le thème et survit au redémarrage', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(
        tester,
        await tester.runAsync(AppearanceSettings.load) ?? AppearanceSettings(),
      );
      await tester.tap(find.byTooltip('À propos'));
      await tester.pumpAndSettle();
      expect(_brightnessOf(tester), Brightness.light);

      await tester.runAsync(() async {
        await tester.tap(find.text('Nuit'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(_brightnessOf(tester), Brightness.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance.themeMode'), 'dark');

      // Redémarrage : le réglage relu donne la nuit d'emblée.
      await tester.pumpWidget(const SizedBox());
      final reloaded = (await tester.runAsync(AppearanceSettings.load))!;
      expect(reloaded.mode, ThemeMode.dark);
      await _pumpApp(tester, reloaded);
      expect(_brightnessOf(tester), Brightness.dark);
    });

    testWidgets('le segment choisi est annoncé', (tester) async {
      await _pumpAbout(tester);
      expect(
        tester.getSemantics(find.text('Jour')),
        matchesSemantics(
          label: 'Jour',
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
    });
  });

  group('captures', () {
    testWidgets('jour', (tester) async {
      await _pumpAbout(tester, withNotifications: true);
      await expectLater(
        find.byType(AboutPage),
        matchesGoldenFile('goldens/apropos-jour.png'),
      );
    });

    testWidgets('nuit', (tester) async {
      await _pumpAbout(
        tester,
        brightness: Brightness.dark,
        withNotifications: true,
      );
      await expectLater(
        find.byType(AboutPage),
        matchesGoldenFile('goldens/apropos-nuit.png'),
      );
    });
  });
}
