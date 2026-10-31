import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'admin_repository.dart';

/// Rôle d'un fournisseur d'IA dans l'ordre d'appel.
enum AiRole {
  primary('Principale'),
  fallback1('Secours 1'),
  fallback2('Secours 2'),
  disabled('Désactivée');

  const AiRole(this.label);
  final String label;

  static AiRole parse(String? v) => switch (v) {
        'primary' => AiRole.primary,
        'fallback_1' => AiRole.fallback1,
        'fallback_2' => AiRole.fallback2,
        _ => AiRole.disabled,
      };
}

/// Consommation d'un fournisseur sur une période.
class AiPeriodUsage {
  const AiPeriodUsage({
    this.calls = 0,
    this.success = 0,
    this.rejected = 0,
    this.errors = 0,
    this.rateLimited = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.costUsd,
    this.avgLatencyMs,
  });

  factory AiPeriodUsage.fromJson(Map<String, dynamic> j) => AiPeriodUsage(
        calls: asInt(j['calls']),
        success: asInt(j['success']),
        rejected: asInt(j['rejected']),
        errors: asInt(j['errors']),
        rateLimited: asInt(j['rate_limited']),
        inputTokens: asInt(j['input_tokens']),
        outputTokens: asInt(j['output_tokens']),
        costUsd: (j['cost_usd'] as num?)?.toDouble(),
        avgLatencyMs: (j['avg_latency_ms'] as num?)?.toInt(),
      );

  final int calls;
  final int success;
  final int rejected;
  final int errors;
  final int rateLimited;
  final int inputTokens;
  final int outputTokens;
  final double? costUsd;
  final int? avgLatencyMs;
}

/// Quota annoncé par le fournisseur lors d'un appel.
class AiQuota {
  const AiQuota({
    this.requestsLimit,
    this.requestsRemaining,
    this.requestsReset,
    this.tokensLimit,
    this.tokensRemaining,
    this.tokensReset,
    this.at,
  });

  static AiQuota? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    int? n(String k) => (j[k] as num?)?.toInt();
    return AiQuota(
      requestsLimit: n('requests_limit'),
      requestsRemaining: n('requests_remaining'),
      requestsReset: j['requests_reset'] as String?,
      tokensLimit: n('tokens_limit'),
      tokensRemaining: n('tokens_remaining'),
      tokensReset: j['tokens_reset'] as String?,
      at: DateTime.tryParse(j['at'] as String? ?? '')?.toLocal(),
    );
  }

  final int? requestsLimit;
  final int? requestsRemaining;
  final String? requestsReset;
  final int? tokensLimit;
  final int? tokensRemaining;
  final String? tokensReset;
  final DateTime? at;
}

class AiProviderInfo {
  const AiProviderInfo({
    required this.name,
    required this.label,
    required this.secret,
    required this.configured,
    required this.role,
    required this.model,
    required this.periods,
    this.lastCallAt,
    this.lastCallStatus,
    this.lastCallError,
    this.lastQuota,
    this.referenceLimits = const {},
  });

  factory AiProviderInfo.fromJson(Map<String, dynamic> j) {
    final usage = asMap(j['usage']);
    final last = asMap(usage['last_call']);
    return AiProviderInfo(
      name: j['name'] as String,
      label: j['label'] as String? ?? j['name'] as String,
      secret: j['secret'] as String? ?? '',
      configured: j['configured'] == true,
      role: AiRole.parse(j['role'] as String?),
      model: j['model'] as String?,
      periods: {
        for (final k in const ['today', 'days_7', 'days_30'])
          k: AiPeriodUsage.fromJson(asMap(usage[k])),
      },
      lastCallAt: DateTime.tryParse(last['at'] as String? ?? '')?.toLocal(),
      lastCallStatus: last['status'] as String?,
      lastCallError: last['error'] as String?,
      lastQuota: AiQuota.fromJson(usage['last_quota']),
      referenceLimits: {
        for (final e in asMap(j['reference_limits']).entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      },
    );
  }

  final String name;
  final String label;
  final String secret;
  final bool configured;
  final AiRole role;
  final String? model;
  final Map<String, AiPeriodUsage> periods;
  final DateTime? lastCallAt;
  final String? lastCallStatus;
  final String? lastCallError;
  final AiQuota? lastQuota;

  /// Limites de référence (offre gratuite) quand le fournisseur n'annonce pas son quota.
  final Map<String, int> referenceLimits;
}

/// Résultat du bouton « Tester ».
class AiTestResult {
  const AiTestResult(
      {required this.ok,
      required this.latencyMs,
      required this.model,
      this.error,
      this.quota});

  final bool ok;
  final int latencyMs;
  final String model;
  final String? error;
  final AiQuota? quota;
}

/// Exception de l'écran Fournisseurs d'IA, déjà formulée pour l'administrateur.
class AiProvidersException implements Exception {
  const AiProvidersException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Principale et secours dans l'ordre, à partir des rôles choisis.
({String? primary, List<String> fallbacks}) orderOf(Map<String, AiRole> roles) {
  String? find(AiRole r) =>
      roles.entries.where((e) => e.value == r).map((e) => e.key).firstOrNull;
  return (
    primary: find(AiRole.primary),
    fallbacks: [
      for (final r in const [AiRole.fallback1, AiRole.fallback2])
        if (find(r) != null) find(r)!,
    ],
  );
}

/// Attribue un rôle : le fournisseur qui l'avait prend l'ancien rôle de celui-ci (échange).
Map<String, AiRole> assignRole(
    Map<String, AiRole> roles, String provider, AiRole role) {
  final next = Map<String, AiRole>.from(roles);
  final previous = next[provider] ?? AiRole.disabled;
  if (role != AiRole.disabled) {
    for (final e in roles.entries) {
      if (e.key != provider && e.value == role) next[e.key] = previous;
    }
  }
  next[provider] = role;
  return next;
}

class AiProvidersRepository {
  AiProvidersRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('ai-providers', body: body);
      return asMap(res.data);
    } on FunctionException catch (e) {
      final d = asMap(e.details);
      throw AiProvidersException(switch (d['error']) {
        'forbidden' => 'Écran réservé au super administrateur.',
        'provider_not_configured' =>
          'Clé absente : ajoutez-la dans les secrets avant d’utiliser cette IA.',
        'invalid_roles' => '${d['message'] ?? 'Choix invalide.'}',
        'model_missing' => 'Choisissez d’abord un modèle.',
        _ => 'Action impossible pour le moment.',
      });
    }
  }

  Future<List<AiProviderInfo>> status() async {
    final data = await _call({'action': 'status'});
    return [
      for (final p in asList(data['providers'])) AiProviderInfo.fromJson(p)
    ];
  }

  Future<List<String>> models(String provider) async {
    final data = await _call({'action': 'models', 'provider': provider});
    return [for (final m in (data['models'] as List? ?? const [])) '$m'];
  }

  Future<AiTestResult> test(String provider, String? model) async {
    final d = await _call({
      'action': 'test',
      'provider': provider,
      if (model != null) 'model': model,
    });
    return AiTestResult(
      ok: d['ok'] == true,
      latencyMs: asInt(d['latency_ms']),
      model: d['model'] as String? ?? model ?? '',
      error: d['error'] as String?,
      quota: AiQuota.fromJson(d['quota']),
    );
  }

  Future<void> save(
      {required String primary,
      required List<String> fallbacks,
      required Map<String, String> models}) async {
    await _call({
      'action': 'save',
      'primary': primary,
      'fallbacks': fallbacks,
      'models': models,
    });
  }
}

final aiProvidersRepositoryProvider = Provider<AiProvidersRepository>(
    (ref) => AiProvidersRepository(ref.watch(supabaseClientProvider)));

final aiProvidersProvider = FutureProvider.autoDispose<List<AiProviderInfo>>(
    (ref) => ref.watch(aiProvidersRepositoryProvider).status());
