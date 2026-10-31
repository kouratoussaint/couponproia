import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> asList(Object? v) =>
    [for (final e in (v as List? ?? const [])) asMap(e)];
int asInt(Object? v) => (v as num?)?.toInt() ?? 0;

/// Message lisible pour une erreur d'administration (le serveur décide toujours).
String adminErrorMessage(Object e) {
  if (e is PostgrestException) {
    if (e.code == '42501') return 'Permission refusée.';
    if (e.code == '22023' || e.code == 'P0002') return e.message;
  }
  return 'Action impossible pour le moment.';
}

class AdminSetting {
  const AdminSetting(
      {required this.key,
      required this.value,
      required this.description,
      required this.isPublic});

  factory AdminSetting.fromJson(Map<String, dynamic> j) => AdminSetting(
        key: j['key'] as String,
        value: j['value'],
        description: j['description'] as String? ?? '',
        isPublic: j['is_public'] == true,
      );

  final String key;
  final Object? value;
  final String description;
  final bool isPublic;
}

class FeatureFlag {
  const FeatureFlag(
      {required this.key, required this.enabled, required this.description});

  factory FeatureFlag.fromJson(Map<String, dynamic> j) => FeatureFlag(
      key: j['key'] as String,
      enabled: j['enabled'] == true,
      description: j['description'] as String? ?? '');

  final String key;
  final bool enabled;
  final String description;
}

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> dashboard(int days) async =>
      asMap(await _client.rpc('admin_dashboard', params: {'p_days': days}));

  Future<List<Map<String, dynamic>>> users(String query) async =>
      asList(await _client.rpc('admin_users',
          params: {'p_query': query.trim().isEmpty ? null : query.trim()}));

  Future<Map<String, dynamic>> user(String id) async =>
      asMap(await _client.rpc('admin_user_detail', params: {'p_user': id}));

  Future<void> setRole(String user, String role, bool grant) =>
      _client.rpc('admin_set_user_role',
          params: {'p_target': user, 'p_role': role, 'p_grant': grant});

  Future<void> setSuspended(String user, bool suspended) =>
      _client.rpc('admin_set_user_suspended',
          params: {'p_target': user, 'p_suspended': suspended});

  Future<void> adjustCredits(String user, int delta, String reason) =>
      _client.rpc('admin_adjust_credits',
          params: {'p_user': user, 'p_delta': delta, 'p_reason': reason});

  Future<void> grantSubscription(
          String user, String plan, int months, String reason) =>
      _client.rpc('admin_grant_subscription', params: {
        'p_user': user,
        'p_plan': plan,
        'p_months': months,
        'p_reason': reason
      });

  /// Pack(s) de crédits offerts : le serveur lit le contenu du pack dans ses réglages.
  Future<int> grantCreditPack(String user, int quantity, String reason) async {
    final r = asMap(await _client.rpc('admin_grant_credit_pack',
        params: {'p_user': user, 'p_quantity': quantity, 'p_reason': reason}));
    return asInt(r['credits']);
  }

  Future<List<FeatureFlag>> flags() async {
    final rows = await _client
        .from('feature_flags')
        .select('key, enabled, description')
        .order('key');
    return rows.map(FeatureFlag.fromJson).toList();
  }

  Future<void> setFlag(String key, bool enabled) =>
      _client.rpc('admin_set_feature_flag',
          params: {'p_key': key, 'p_enabled': enabled});

  Future<List<AdminSetting>> settings() async {
    final rows = await _client
        .from('app_settings')
        .select('key, value, description, is_public')
        .order('key');
    return rows.map(AdminSetting.fromJson).toList();
  }

  Future<void> setSetting(String key, Object? value) => _client
      .rpc('admin_set_setting', params: {'p_key': key, 'p_value': value});

  Future<List<Map<String, dynamic>>> payments(String? status) async =>
      asList(await _client.rpc('admin_payments', params: {'p_status': status}));

  Future<Map<String, dynamic>> costs(int days) async =>
      asMap(await _client.rpc('admin_costs', params: {'p_days': days}));

  Future<List<Map<String, dynamic>>> promoCodes() async =>
      asList(await _client.rpc('admin_promo_codes'));

  Future<void> savePromo({
    required String code,
    required String description,
    required int percentOff,
    required String appliesTo,
    required List<String> planCodes,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxUses,
    required bool active,
  }) =>
      _client.rpc('admin_save_promo', params: {
        'p_code': code,
        'p_description': description,
        'p_percent': percentOff,
        'p_applies_to': appliesTo,
        'p_plan_codes': planCodes,
        'p_starts': startsAt?.toUtc().toIso8601String(),
        'p_ends': endsAt?.toUtc().toIso8601String(),
        'p_max_uses': maxUses,
        'p_active': active,
      });

  /// Enregistre un remboursement déjà effectué chez l'opérateur : droits retirés, journalisé.
  Future<Map<String, dynamic>> refundPayment(String id, String reason) async =>
      asMap(await _client.rpc('admin_refund_payment',
          params: {'p_payment': id, 'p_reason': reason}));

  Future<List<Map<String, dynamic>>> audit(String? action) async =>
      asList(await _client
          .rpc('admin_audit', params: {'p_limit': 150, 'p_action': action}));
}

final adminRepositoryProvider = Provider<AdminRepository>(
    (ref) => AdminRepository(ref.watch(supabaseClientProvider)));

final adminDashboardProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>(
        (ref, days) => ref.watch(adminRepositoryProvider).dashboard(days));

final adminUsersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
        (ref, q) => ref.watch(adminRepositoryProvider).users(q));

final adminUserProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
        (ref, id) => ref.watch(adminRepositoryProvider).user(id));

final adminFlagsProvider = FutureProvider.autoDispose<List<FeatureFlag>>(
    (ref) => ref.watch(adminRepositoryProvider).flags());

final adminSettingsProvider = FutureProvider.autoDispose<List<AdminSetting>>(
    (ref) => ref.watch(adminRepositoryProvider).settings());

final adminPaymentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>(
        (ref, s) => ref.watch(adminRepositoryProvider).payments(s));

final adminAuditProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>(
        (ref, a) => ref.watch(adminRepositoryProvider).audit(a));

final adminPromosProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => ref.watch(adminRepositoryProvider).promoCodes());

final adminCostsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>(
        (ref, days) => ref.watch(adminRepositoryProvider).costs(days));
