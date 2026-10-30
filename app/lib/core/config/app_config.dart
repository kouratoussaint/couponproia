/// Configuration injectée à la compilation via `--dart-define`.
///
/// Seules des valeurs publiques entrent dans l'APK : l'URL du projet Supabase
/// et sa clé publique (anon / publishable). Aucune clé secrète (IA, données
/// sportives, paiement) ne doit jamais apparaître ici.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.environment,
  });

  static const AppConfig fromEnvironment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'dev'),
  );

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// `dev` (staging) ou `prod`.
  final String environment;

  bool get isConfigured =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.trim().isNotEmpty;

  bool get isProduction => environment == 'prod';
}
