import 'features/profile/data/language_sync.dart';
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/i18n/tr.dart';
import 'core/config/app_config.dart';
import 'core/monitoring/error_reporter.dart';
import 'core/offline/offline_http_client.dart';
import 'core/offline/offline_store.dart';
import 'core/providers.dart';

/// Écoute du retour dans l'app (jour d'activité), conservée pendant toute la vie de l'app.
AppLifecycleListener? appLifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment;
  final prefs = await SharedPreferences.getInstance();

  // Langue de l'interface, fixée avant l'affichage (changer de langue redémarre l'app).
  await loadLanguage(prefs.getString(languagePrefKey) ??
      defaultLanguage(PlatformDispatcher.instance.locale.languageCode));

  // Plantages et lenteurs (sans contenu personnel, désactivable dans le Profil).
  final reporter = ErrorReporter(prefs);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reporter.record('flutter', details.exception, details.stack,
        context: details.context?.toDescription());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.record('dart', error, stack);
    return true;
  };
  try {
    final info = await PackageInfo.fromPlatform();
    reporter
      ..version = info.version
      ..build = int.tryParse(info.buildNumber);
  } catch (_) {}

  if (config.isConfigured) {
    // Lecture hors connexion : dernières réponses enregistrées dans le dossier privé de l'app.
    OfflineStore store = MemoryOfflineStore();
    if (!kIsWeb) {
      try {
        final dir = await getApplicationSupportDirectory();
        store = FileOfflineStore(Directory('${dir.path}/offline'));
      } catch (_) {}
    }
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
      httpClient:
          OfflineHttpClient(http.Client(), store, onSlow: reporter.recordSlow),
    );
    // Jour d'activité (rétention) : une fois par jour, à l'ouverture et au retour dans l'app.
    Future<void> touchActivity() async {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final today = '${now.year}-${now.month}-${now.day}';
      final key = 'activity_day_${user.id}';
      if (prefs.getString(key) == today) return;
      try {
        await client.rpc('touch_activity');
        await prefs.setString(key, today);
      } catch (_) {}
    }

    appLifecycle = AppLifecycleListener(onResume: touchActivity);
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        store.clear();
        offlineSince.value = null;
      } else if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession) {
        reporter.flush();
        touchActivity();
        syncAccountLanguage(Supabase.instance.client);
      }
    });
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(prefs),
        errorReporterProvider.overrideWithValue(reporter),
      ],
      child: const CouponProApp(),
    ),
  );
}
