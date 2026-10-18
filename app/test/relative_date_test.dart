import 'package:flutter_test/flutter_test.dart';
import 'package:votedujour/src/relative_date.dart';

void main() {
  // Jour du vote tel que le lit le contrat : minuit UTC.
  final vendredi = DateTime.utc(2026, 10, 16);

  String label(DateTime now) => relativeDayLabel(vendredi, now: now);

  test('aujourd\'hui, de minuit à minuit (heure locale)', () {
    expect(label(DateTime(2026, 10, 16, 0, 0)), "Aujourd'hui");
    expect(label(DateTime(2026, 10, 16, 23, 59, 59)), "Aujourd'hui");
  });

  test('passe à « Hier » à minuit pile', () {
    expect(label(DateTime(2026, 10, 16, 23, 59, 59, 999)), "Aujourd'hui");
    expect(label(DateTime(2026, 10, 17)), 'Hier');
    expect(label(DateTime(2026, 10, 17, 23, 59)), 'Hier');
  });

  test('compte les jours de calendrier, week-end compris', () {
    // Vote du vendredi, lu le lundi.
    expect(label(DateTime(2026, 10, 19, 8)), 'Il y a 3 jours');
    expect(label(DateTime(2026, 10, 18, 8)), 'Il y a 2 jours');
    expect(label(DateTime(2026, 10, 22, 23)), 'Il y a 6 jours');
  });

  test('au-delà de six jours, la date complète', () {
    expect(label(DateTime(2026, 10, 23)), '16 octobre 2026');
    expect(
      relativeDayLabel(DateTime.utc(2026, 9, 1), now: DateTime(2026, 10, 17)),
      '1er septembre 2026',
    );
  });

  test('juste à travers le changement d\'heure et le changement de mois', () {
    // Passage à l'heure d'hiver le 25 octobre 2026 (journée de 25 h en
    // France) : l'écart reste d'un jour.
    expect(
      relativeDayLabel(
        DateTime.utc(2026, 10, 24),
        now: DateTime(2026, 10, 25, 23),
      ),
      'Hier',
    );
    expect(
      relativeDayLabel(
        DateTime.utc(2026, 10, 31),
        now: DateTime(2026, 11, 2, 9),
      ),
      'Il y a 2 jours',
    );
    expect(
      relativeDayLabel(DateTime.utc(2026, 12, 31), now: DateTime(2027, 1, 1)),
      'Hier',
    );
  });

  test('une date future (horloge décalée) reste « Aujourd\'hui »', () {
    expect(label(DateTime(2026, 10, 15, 22)), "Aujourd'hui");
  });

  test('intertitres de la liste : jour de la semaine et date (#29)', () {
    String group(DateTime day, DateTime now) => dayGroupLabel(day, now: now);
    expect(group(vendredi, DateTime(2026, 10, 16, 9)), "Aujourd'hui");
    expect(group(vendredi, DateTime(2026, 10, 17, 9)), 'Hier');
    expect(
      group(DateTime.utc(2026, 10, 13), DateTime(2026, 10, 18)),
      'Mardi 13 octobre',
    );
    expect(
      group(DateTime.utc(2026, 10, 12), DateTime(2026, 10, 18)),
      'Lundi 12 octobre',
    );
    expect(
      group(DateTime.utc(2026, 11, 1), DateTime(2026, 11, 20)),
      'Dimanche 1er novembre',
    );
    expect(
      group(DateTime.utc(2025, 4, 1), DateTime(2026, 10, 18)),
      'Mardi 1er avril 2025',
    );
  });
}
