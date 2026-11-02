import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../analysis/data/analysis_repository.dart';
import 'coupon_models.dart';
import 'coupon_phase.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

const _selectionColumns =
    'position, selection_key, odd, odd_best, bookmakers, odds_captured_at, '
    'model_probability, implied_probability, edge, reliability, justification, justification_en, result, '
    'match:matches(id, kickoff_at, status, home_goals, away_goals, '
    'home:teams!matches_home_team_fk(name, logo_url), away:teams!matches_away_team_fk(name, logo_url), '
    'competition:competitions(name))';

const _couponColumns =
    'id, category, title, description, risk_level, total_odd, combined_probability, '
    'implied_probability, status, status_note, publish_at, published_at, first_kickoff_at, last_kickoff_at, '
    'engine_version, data_source, result, settled_odd, settled_at, created_at, coupon_selections($_selectionColumns)';

class CouponRepository {
  CouponRepository(this._client);

  final SupabaseClient _client;

  /// L'analyse est servie par coupon_analyses(), qui la masque (comme les sélections) pour un
  /// coupon réservé tant que le premier match n'a pas commencé.
  Future<List<Coupon>> _coupons(List<dynamic> rows) async {
    final maps = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
    if (maps.isEmpty) return const [];
    final res = await _client.rpc('coupon_analyses', params: {
      'p_ids': [for (final m in maps) m['id']]
    });
    final byId = {
      for (final a in res as List)
        (a as Map)['id'] as String: Map<String, dynamic>.from(a),
    };
    return [
      for (final m in maps)
        Coupon.fromJson({
          ...m,
          'analysis': byId[m['id']]?['analysis'],
          'locked': byId[m['id']]?['locked'] == true,
        }),
    ];
  }

  /// Coupons publiés (et retirés, pour la transparence), les plus récents d'abord.
  Future<List<Coupon>> published() async {
    final rows = await _client
        .from('coupons')
        .select(_couponColumns)
        .inFilter('status', ['published', 'withdrawn'])
        .order('published_at', ascending: false)
        .limit(100);
    return await _coupons(rows);
  }

  /// Coupons publiés pas encore décidés (onglets « À jouer » et « En cours »).
  Future<List<Coupon>> active() async {
    final rows = await _client
        .from('coupons')
        .select(_couponColumns)
        .eq('status', 'published')
        .isFilter('result', null)
        .order('first_kickoff_at')
        .limit(200);
    return await _coupons(rows);
  }

  /// Coupons décidés (gagnés, perdus, annulés), les plus récents d'abord ; [limit] grandit
  /// avec « Voir les jours précédents ». Rien n'est jamais effacé : tout l'historique reste lisible.
  Future<List<Coupon>> decided({int limit = 60}) async {
    final rows = await _client
        .from('coupons')
        .select(_couponColumns)
        .eq('status', 'published')
        .not('result', 'is', null)
        .order('settled_at', ascending: false, nullsFirst: false)
        .limit(limit);
    return await _coupons(rows);
  }

  /// Coupons retirés par l'équipe (affichés grisés, repliés en bas des résultats).
  Future<List<Coupon>> withdrawnList() async {
    final rows = await _client
        .from('coupons')
        .select(_couponColumns)
        .eq('status', 'withdrawn')
        .order('published_at', ascending: false)
        .limit(50);
    return await _coupons(rows);
  }

  Future<Coupon?> coupon(String id) async {
    final row = await _client
        .from('coupons')
        .select(
            '$_couponColumns, coupon_status_history(from_status, to_status, reason, created_at)')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : (await _coupons([row])).first;
  }

  /// Cote médiane actuelle de chaque issue (« match:clé »), pour l'afficher à côté de la cote publiée.
  Future<Map<String, double>> currentOdds(List<int> matchIds) async {
    if (matchIds.isEmpty) return const {};
    final rows = await _client
        .from('latest_odds')
        .select('match_id, market_code, outcome_code, line, odd_median')
        .inFilter('match_id', matchIds);
    final out = <String, double>{};
    for (final r in rows) {
      final line =
          r['line'] == null ? '' : '.${_line((r['line'] as num).toDouble())}';
      out['${r['match_id']}:${r['market_code']}.${r['outcome_code']}$line'] =
          (r['odd_median'] as num).toDouble();
    }
    return out;
  }

  static String _line(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  // --- Administration (generation.manage) --------------------------------------------------

  Future<List<CouponProfile>> profiles() async {
    final rows = await _client.from('coupon_profiles').select().order('sort');
    return rows.map(CouponProfile.fromJson).toList();
  }

  Future<List<GenerationRun>> runs() async {
    final rows = await _client
        .from('generation_runs')
        .select(
            'id, trigger, slot_key, status, coupons_created, candidates, reasons, started_at, profile:coupon_profiles(name)')
        .order('started_at', ascending: false)
        .limit(40);
    return rows.map(GenerationRun.fromJson).toList();
  }

  /// Coupons pas encore publiés (à valider ou programmés).
  Future<List<Coupon>> upcomingUnpublished() async {
    final rows = await _client
        .from('coupons')
        .select(_couponColumns)
        .inFilter('status', ['pending_review', 'ready'])
        .order('publish_at')
        .limit(50);
    return await _coupons(rows);
  }

  /// Historique des coupons de la plateforme (équipe) : tous statuts, avec leurs changements.
  Future<List<Coupon>> history({int limit = 60}) async {
    final rows = await _client
        .from('coupons')
        .select(
            '$_couponColumns, coupon_status_history(from_status, to_status, reason, created_at)')
        .order('updated_at', ascending: false)
        .limit(limit);
    return sortByLastAction(await _coupons(rows));
  }

  /// Publication immédiate (coupon programmé ou à valider), après un dernier contrôle serveur.
  Future<void> publishNow(String couponId, {bool force = false}) async {
    try {
      await _client.functions.invoke('coupon-engine', body: {
        'job': 'publish_now',
        'coupon_id': couponId,
        if (force) 'force': true,
      });
    } on FunctionException catch (e) {
      throw _engineError(e, tr('Publication impossible pour le moment.'));
    }
  }

  /// Modification d'un coupon généré (avant publication) : sélections remplacées, totaux recalculés.
  Future<void> editCoupon(String couponId,
      {required List<({int matchId, String key})> selections,
      required String note,
      String? title,
      bool force = false}) async {
    try {
      await _client.functions.invoke('coupon-engine', body: {
        'job': 'edit_coupon',
        'coupon_id': couponId,
        'selections': [
          for (final s in selections) {'match_id': s.matchId, 'key': s.key}
        ],
        'note': note,
        if (title != null) 'title': title,
        if (force) 'force': true,
      });
    } on FunctionException catch (e) {
      throw _engineError(e, tr('Modification impossible pour le moment.'));
    }
  }

  /// Copie d'un coupon retiré, à modifier puis à valider. Renvoie l'identifiant de la copie.
  Future<String> duplicateCoupon(String couponId) async {
    try {
      final res = await _client.functions.invoke('coupon-engine',
          body: {'job': 'duplicate_coupon', 'coupon_id': couponId});
      return (res.data as Map)['id'] as String;
    } on FunctionException catch (e) {
      throw _engineError(e, tr('Duplication impossible pour le moment.'));
    }
  }

  static Exception _engineError(FunctionException e, String fallback) {
    final d = e.details is Map
        ? Map<String, dynamic>.from(e.details as Map)
        : const <String, dynamic>{};
    if (d['error'] == 'ai_contradiction') {
      return CouponAiConflict([
        for (final i in (d['items'] as List? ?? const [])) '$i',
      ]);
    }
    return AnalysisException(d['message'] as String? ??
        (e.status == 403
            ? tr('Action réservée au super administrateur.')
            : fallback));
  }

  Future<Map<String, dynamic>> generateNow(int profileId) async {
    try {
      final res = await _client.functions.invoke('coupon-engine',
          body: {'job': 'generate', 'profile_id': profileId});
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      throw AnalysisException(analysisErrorMessage(e.status, e.details));
    }
  }

  Future<void> review(String couponId,
          {required bool approve, String? reason}) =>
      _client.rpc('admin_review_coupon', params: {
        'p_coupon': couponId,
        'p_approve': approve,
        'p_reason': reason
      });

  Future<void> withdraw(String couponId, String reason) =>
      _client.rpc('admin_withdraw_coupon',
          params: {'p_coupon': couponId, 'p_reason': reason});

  /// Suppression définitive de coupons retirés (équipe) ; renvoie le nombre supprimé.
  Future<int> deleteWithdrawn(List<String> ids, String reason) async =>
      ((await _client.rpc('admin_delete_withdrawn_coupons',
              params: {'p_ids': ids, 'p_reason': reason})) as num)
          .toInt();

  Future<void> updateProfile(int profileId, Map<String, dynamic> patch) =>
      _client.rpc('admin_update_coupon_profile',
          params: {'p_profile': profileId, 'p_patch': patch});
}

final couponRepositoryProvider = Provider<CouponRepository>(
  (ref) => CouponRepository(ref.watch(supabaseClientProvider)),
);

final publishedCouponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(couponRepositoryProvider).published(),
);

final activeCouponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(couponRepositoryProvider).active(),
);

/// Nombre de résultats chargés : la page en demande davantage avec « Voir plus ».
const decidedPageSize = 60;

final decidedCouponsProvider =
    FutureProvider.autoDispose.family<List<Coupon>, int>(
  (ref, limit) => ref.watch(couponRepositoryProvider).decided(limit: limit),
);

final withdrawnCouponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(couponRepositoryProvider).withdrawnList(),
);

/// Après une action (retrait, suppression, génération) : toutes les listes sont relues.
/// Listes de l'équipe (à valider, programmés, historique) et listes publiques.
void invalidateCouponAdminLists(WidgetRef ref) {
  ref.invalidate(unpublishedCouponsProvider);
  ref.invalidate(couponHistoryProvider);
  invalidateCouponLists(ref);
}

void invalidateCouponLists(WidgetRef ref) {
  ref.invalidate(publishedCouponsProvider);
  ref.invalidate(activeCouponsProvider);
  ref.invalidate(decidedCouponsProvider);
  ref.invalidate(withdrawnCouponsProvider);
}

final couponProvider = FutureProvider.autoDispose.family<Coupon?, String>(
  (ref, id) => ref.watch(couponRepositoryProvider).coupon(id),
);

final currentOddsProvider = FutureProvider.autoDispose
    .family<Map<String, double>, String>((ref, couponId) async {
  final coupon = await ref.watch(couponProvider(couponId).future);
  if (coupon == null) return const {};
  return ref
      .watch(couponRepositoryProvider)
      .currentOdds(coupon.selections.map((s) => s.match.id).toList());
});

final couponProfilesProvider = FutureProvider.autoDispose<List<CouponProfile>>(
  (ref) => ref.watch(couponRepositoryProvider).profiles(),
);

final generationRunsProvider = FutureProvider.autoDispose<List<GenerationRun>>(
  (ref) => ref.watch(couponRepositoryProvider).runs(),
);

final unpublishedCouponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(couponRepositoryProvider).upcomingUnpublished(),
);

final couponHistoryProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(couponRepositoryProvider).history(),
);

/// Une sélection contredit l'analyse IA de son match : l'équipe peut passer outre.
class CouponAiConflict implements Exception {
  const CouponAiConflict(this.items);
  final List<String> items;
  @override
  String toString() => items.join('\n');
}
