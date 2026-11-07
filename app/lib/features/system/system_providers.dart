import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Mentions affichées si la configuration distante est injoignable (hors ligne).
final fallbackDisclaimers = [
  tr('Les pronostics sont des estimations, pas des certitudes.'),
  tr('Les résultats sportifs sont incertains.'),
  tr('Les performances passées ne garantissent pas les performances futures.'),
  tr('Les probabilités affichées sont des estimations.'),
  tr('Les cotes peuvent changer à tout moment.'),
  tr('Les données peuvent être incomplètes.'),
  tr('Aucun gain n’est garanti.'),
  tr('Coupon Pro IA n’est pas un bookmaker : aucun pari n’est placé dans l’application.'),
  tr('Service réservé aux personnes majeures.'),
];

/// Interrupteurs des modules, pilotés depuis l'administration sans nouvel APK.
final featureFlagsProvider = FutureProvider<Map<String, bool>>((ref) async {
  ref.watch(currentUserProvider);
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('feature_flags')
      .select('key, enabled');
  return {for (final row in rows) row['key'] as String: row['enabled'] as bool};
});

/// Permissions de l'utilisateur connecté (affichage seulement : le serveur contrôle).
final myPermissionsProvider = FutureProvider<Set<String>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return <String>{};
  final result = await ref.watch(supabaseClientProvider).rpc('my_permissions');
  return {for (final p in (result as List)) p.toString()};
});

/// Réglages publics (devise, tarifs, mentions…).
final publicSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('app_settings')
      .select('key, value')
      .eq('is_public', true);
  return {for (final row in rows) row['key'] as String: row['value']};
});

final disclaimersProvider = FutureProvider<List<String>>((ref) async {
  try {
    final settings = await ref.watch(publicSettingsProvider.future);
    final value = settings['legal.disclaimers'];
    if (value is List && value.isNotEmpty) {
      return value.map((e) => e.toString()).toList();
    }
  } catch (_) {
    // hors ligne : mentions locales
  }
  return fallbackDisclaimers;
});

class AppVersionInfo {
  const AppVersionInfo({
    required this.versionName,
    required this.buildNumber,
    required this.minSupportedBuild,
    this.downloadUrl,
    this.releaseNotes,
    this.sha256,
    this.sizeBytes,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) => AppVersionInfo(
        versionName: json['version_name'] as String,
        buildNumber: json['build_number'] as int,
        minSupportedBuild: json['min_supported_build'] as int,
        downloadUrl: json['download_url'] as String?,
        releaseNotes: json['release_notes'] as String?,
        sha256: json['sha256'] as String?,
        sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      );

  final String versionName;
  final int buildNumber;
  final int minSupportedBuild;
  final String? downloadUrl;
  final String? releaseNotes;

  /// Empreinte et taille de l'APK (LOT 26) : sans elles, repli sur le navigateur.
  final String? sha256;
  final int? sizeBytes;

  bool get installableInApp =>
      downloadUrl != null &&
      sha256 != null &&
      sha256!.length == 64 &&
      (sizeBytes ?? 0) > 0;

  double get sizeMb => (sizeBytes ?? 0) / 1000000;
}

enum UpdateKind { none, optional, required }

/// Compare la version installée à la dernière version publiée.
UpdateKind updateKindFor(
    {required int installedBuild, AppVersionInfo? latest}) {
  if (latest == null || installedBuild <= 0) return UpdateKind.none;
  if (installedBuild < latest.minSupportedBuild) return UpdateKind.required;
  if (installedBuild < latest.buildNumber) return UpdateKind.optional;
  return UpdateKind.none;
}

final installedPackageProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

final latestAndroidVersionProvider =
    FutureProvider<AppVersionInfo?>((ref) async {
  // Mises à jour par APK : Android uniquement (iOS et web passeront par leurs propres canaux).
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  final row = await ref
      .watch(supabaseClientProvider)
      .from('app_versions')
      .select(
          'version_name, build_number, min_supported_build, download_url, release_notes, sha256, size_bytes')
      .eq('platform', 'android')
      .order('build_number', ascending: false)
      .limit(1)
      .maybeSingle();
  return row == null ? null : AppVersionInfo.fromJson(row);
});

/// Saison d'archive affichée à la place de la saison en cours (offre gratuite du
/// fournisseur), ou null.
final archiveSeasonProvider = FutureProvider<int?>((ref) async {
  final settings = await ref.watch(publicSettingsProvider.future);
  final value = settings['sports.archive_season'];
  return value is num ? value.toInt() : null;
});
