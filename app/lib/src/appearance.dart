import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _modeKey = 'appearance.themeMode';

/// Réglage d'apparence de la page À propos (#76) : Auto (celle du
/// téléphone), Jour ou Nuit. Auto par défaut ; le choix est gardé dans les
/// préférences et relu au lancement.
class AppearanceSettings extends ChangeNotifier {
  AppearanceSettings({ThemeMode mode = ThemeMode.system}) : _mode = mode;

  /// Réglage enregistré, Auto s'il n'y en a pas (ou s'il est illisible).
  static Future<AppearanceSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modeKey);
    return AppearanceSettings(
      mode: ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      ),
    );
  }

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Change d'apparence et l'enregistre.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }
}

/// Met le réglage d'apparence à portée de la page À propos.
class AppearanceScope extends InheritedNotifier<AppearanceSettings> {
  const AppearanceScope({
    super.key,
    required AppearanceSettings super.notifier,
    required super.child,
  });

  static AppearanceSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}
