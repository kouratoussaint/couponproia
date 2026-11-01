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
import 'core/config/app_config.dart';
import 'core/monitoring/error_reporter.dart';
import 'core/offline/offline_http_client.dart';
import 'core/offline/offline_store.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment;
  final prefs = await SharedPreferences.getInstance();

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
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        store.clear();
        offlineSince.value = null;
      } else if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession) {
        reporter.flush();
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
