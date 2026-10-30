import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Nom stocké en base et en local pour chaque mode de thème.
String themeModeToName(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

ThemeMode themeModeFromName(String? name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Mode de thème choisi par l'utilisateur.
///
/// Stocké localement pour s'appliquer dès le démarrage (même hors ligne) et
/// synchronisé avec `user_preferences` pour suivre l'utilisateur d'un appareil à l'autre.
class ThemeModeController extends Notifier<ThemeMode> {
  static const storageKey = 'theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return themeModeFromName(prefs.getString(storageKey));
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(storageKey, themeModeToName(mode));
    await _pushRemote(mode);
  }

  /// Applique la préférence enregistrée en base (appelé après connexion).
  Future<void> pullRemote() async {
    if (!ref.read(appConfigProvider).isConfigured) return;
    final client = ref.read(supabaseClientProvider);
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await client
          .from('user_preferences')
          .select('theme_mode')
          .eq('user_id', user.id)
          .maybeSingle();
      final remote = themeModeFromName(row?['theme_mode'] as String?);
      if (remote != state) {
        state = remote;
        await ref
            .read(sharedPreferencesProvider)
            .setString(storageKey, themeModeToName(remote));
      }
    } catch (_) {
      // Hors ligne : on garde la préférence locale.
    }
  }

  Future<void> _pushRemote(ThemeMode mode) async {
    if (!ref.read(appConfigProvider).isConfigured) return;
    final client = ref.read(supabaseClientProvider);
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await client
          .from('user_preferences')
          .update({'theme_mode': themeModeToName(mode)}).eq('user_id', user.id);
    } catch (_) {
      // Synchronisation au prochain changement : la valeur locale fait foi.
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
