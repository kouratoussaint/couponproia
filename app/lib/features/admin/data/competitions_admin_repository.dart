import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'admin_repository.dart';

/// État d'une compétition (LOT 25).
enum CompetitionStatus { active, observation, inactive }

CompetitionStatus competitionStatusOf(String? v) => switch (v) {
      'active' => CompetitionStatus.active,
      'observation' => CompetitionStatus.observation,
      _ => CompetitionStatus.inactive,
    };

/// Qualité mesurée du moteur sur une compétition (saisons regroupées).
class CompetitionQuality {
  const CompetitionQuality(
      {required this.matches,
      this.brierModel,
      this.brierBaseline,
      this.verdict});

  factory CompetitionQuality.fromJson(Map<String, dynamic> j) =>
      CompetitionQuality(
        matches: asInt(j['matches']),
        brierModel: (j['brier_model'] as num?)?.toDouble(),
        brierBaseline: (j['brier_baseline'] as num?)?.toDouble(),
        verdict: j['verdict'] as bool?,
      );

  final int matches;
  final double? brierModel;
  final double? brierBaseline;

  /// true : le moteur bat la référence ; false : non ; null : moins de 100 matchs évalués.
  final bool? verdict;
}

class AdminCompetition {
  const AdminCompetition({
    required this.id,
    required this.name,
    required this.displayName,
    required this.status,
    required this.priority,
    this.country,
    this.logoUrl,
    this.providerRef = '',
    this.qualityOverride = false,
    this.lastSyncAt,
    this.matches14d = 0,
    this.openCoupons = 0,
    this.quality,
  });

  factory AdminCompetition.fromJson(Map<String, dynamic> j) => AdminCompetition(
        id: asInt(j['id']),
        name: j['name'] as String? ?? '?',
        displayName:
            j['display_name'] as String? ?? j['name'] as String? ?? '?',
        status: competitionStatusOf(j['status'] as String?),
        priority: asInt(j['priority']),
        country: j['country'] as String?,
        logoUrl: j['logo_url'] as String?,
        providerRef: j['provider_ref'] as String? ?? '',
        qualityOverride: j['quality_override'] == true,
        lastSyncAt:
            DateTime.tryParse(j['last_sync_at'] as String? ?? '')?.toLocal(),
        matches14d: asInt(j['matches_14d']),
        openCoupons: asInt(j['open_coupons']),
        quality: j['quality'] is Map
            ? CompetitionQuality.fromJson(asMap(j['quality']))
            : null,
      );

  final int id;
  final String name;
  final String displayName;
  final CompetitionStatus status;
  final int priority;
  final String? country;
  final String? logoUrl;
  final String providerRef;
  final bool qualityOverride;
  final DateTime? lastSyncAt;
  final int matches14d;
  final int openCoupons;
  final CompetitionQuality? quality;

  /// Admise dans les coupons automatiques : active, et verdict positif ou forçage.
  bool get inAutomaticCoupons =>
      status == CompetitionStatus.active &&
      (qualityOverride || quality?.verdict == true);
}

/// Compétition du catalogue du fournisseur.
class CatalogLeague {
  const CatalogLeague({
    required this.providerRef,
    required this.name,
    this.country,
    this.logoUrl,
    this.type,
    this.currentSeason,
    this.odds = false,
    this.lineups = false,
    this.statistics = false,
    this.competitionId,
    this.status,
  });

  factory CatalogLeague.fromJson(Map<String, dynamic> j) {
    final c = asMap(j['coverage']);
    return CatalogLeague(
      providerRef: j['provider_ref'] as String? ?? '',
      name: j['name'] as String? ?? '?',
      country: j['country'] as String?,
      logoUrl: j['logo_url'] as String?,
      type: j['type'] as String?,
      currentSeason: (j['current_season'] as num?)?.toInt(),
      odds: c['odds'] == true,
      lineups: c['lineups'] == true,
      statistics: c['statistics'] == true,
      competitionId: (j['competition_id'] as num?)?.toInt(),
      status: j['status'] == null
          ? null
          : competitionStatusOf(j['status'] as String?),
    );
  }

  final String providerRef;
  final String name;
  final String? country;
  final String? logoUrl;
  final String? type;
  final int? currentSeason;
  final bool odds;
  final bool lineups;
  final bool statistics;
  final int? competitionId;
  final CompetitionStatus? status;

  bool get tracked => status != null && status != CompetitionStatus.inactive;
}

class CatalogSearch {
  const CatalogSearch(
      {required this.size, this.refreshedAt, this.results = const []});

  final int size;
  final DateTime? refreshedAt;
  final List<CatalogLeague> results;
}

/// Résultat d'un changement d'état : avertissement éventuel du serveur.
typedef StatusChange = ({String? warning, int openCoupons});

class CompetitionsAdminRepository {
  CompetitionsAdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<AdminCompetition>> list() async {
    final res = await _client.rpc('admin_competitions');
    return [for (final j in asList(res)) AdminCompetition.fromJson(j)];
  }

  Future<CatalogSearch> search(String query) async {
    final res = asMap(await _client
        .rpc('admin_search_league_catalog', params: {'p_query': query}));
    return CatalogSearch(
      size: asInt(res['catalog_size']),
      refreshedAt:
          DateTime.tryParse(res['refreshed_at'] as String? ?? '')?.toLocal(),
      results: [
        for (final j in asList(res['results'])) CatalogLeague.fromJson(j)
      ],
    );
  }

  Future<void> add(String providerRef) => _client
      .rpc('admin_add_competition', params: {'p_provider_ref': providerRef});

  Future<StatusChange> setStatus(int id, CompetitionStatus status) async {
    final res = asMap(await _client.rpc('admin_set_competition_status',
        params: {'p_id': id, 'p_status': status.name}));
    return (
      warning: res['warning'] as String?,
      openCoupons: asInt(res['open_coupons'])
    );
  }

  Future<void> setPriority(int id, int priority) =>
      _client.rpc('admin_set_competition_priority',
          params: {'p_id': id, 'p_priority': priority});

  Future<void> setOverride(int id, bool enabled) =>
      _client.rpc('admin_set_competition_override',
          params: {'p_id': id, 'p_enabled': enabled});

  /// Actualise le catalogue tout de suite (sinon : chaque lundi).
  Future<void> refreshCatalog() =>
      _client.functions.invoke('sports-sync', body: {'job': 'catalog'});
}

final competitionsAdminRepositoryProvider =
    Provider<CompetitionsAdminRepository>((ref) =>
        CompetitionsAdminRepository(ref.watch(supabaseClientProvider)));

final adminCompetitionsProvider =
    FutureProvider.autoDispose<List<AdminCompetition>>(
        (ref) => ref.watch(competitionsAdminRepositoryProvider).list());

final catalogSearchProvider = FutureProvider.autoDispose
    .family<CatalogSearch, String>(
        (ref, q) => ref.watch(competitionsAdminRepositoryProvider).search(q));
