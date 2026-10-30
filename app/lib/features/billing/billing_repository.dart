import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../assistant/data/assistant_models.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class PlanOffer {
  const PlanOffer({
    required this.code,
    required this.name,
    required this.monthlyXof,
    required this.aiCredits,
    required this.allCoupons,
    required this.analysesPerDay,
  });

  factory PlanOffer.fromJson(Map<String, dynamic> j) {
    final f = j['features'] is Map
        ? Map<String, dynamic>.from(j['features'] as Map)
        : const <String, dynamic>{};
    return PlanOffer(
      code: j['code'] as String,
      name: j['name'] as String,
      monthlyXof: _i(j['monthly_xof']),
      aiCredits: _i(j['ai_credits']),
      allCoupons: f['coupon_categories'] == 'all',
      analysesPerDay: f['match_analyses_per_day'] == null
          ? null
          : _i(f['match_analyses_per_day']),
    );
  }

  final String code;
  final String name;
  final int monthlyXof;
  final int aiCredits;
  final bool allCoupons;
  final int? analysesPerDay;

  /// Même règle d'arrondi que le serveur (qui recalcule de toute façon le prix).
  int priceFor({required bool annual, required int discountPercent}) => annual
      ? ((monthlyXof * 12 * (1 - discountPercent / 100)) / 100).round() * 100
      : monthlyXof;
}

class Entitlements {
  const Entitlements(
      {required this.plan,
      required this.credits,
      this.periodEnd,
      this.allCoupons = false});

  factory Entitlements.fromJson(Map<String, dynamic> j) {
    final f = j['features'] is Map
        ? Map<String, dynamic>.from(j['features'] as Map)
        : const <String, dynamic>{};
    return Entitlements(
      plan: j['plan'] as String? ?? 'FREE',
      periodEnd: j['period_end'] == null
          ? null
          : DateTime.parse(j['period_end'] as String).toLocal(),
      credits: Credits.fromJson(Map<String, dynamic>.from(j['credits'] as Map)),
      allCoupons: f['coupon_categories'] == 'all',
    );
  }

  final String plan;
  final DateTime? periodEnd;
  final Credits credits;
  final bool allCoupons;
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.kind,
    required this.amountXof,
    required this.status,
    required this.createdAt,
    this.planCode,
    this.period,
    this.credits,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: j['id'] as String,
        kind: j['kind'] as String,
        planCode: j['plan_code'] as String?,
        period: j['period'] as String?,
        credits: j['credits'] == null ? null : _i(j['credits']),
        amountXof: _i(j['amount_xof']),
        status: j['status'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  final String id;
  final String kind;
  final String? planCode;
  final String? period;
  final int? credits;
  final int amountXof;
  final String status;
  final DateTime createdAt;
}

class BillingException implements Exception {
  const BillingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BillingRepository {
  BillingRepository(this._client);

  final SupabaseClient _client;

  Future<Entitlements> entitlements() async => Entitlements.fromJson(
      Map<String, dynamic>.from(await _client.rpc('my_entitlements') as Map));

  Future<List<PaymentRecord>> payments() async {
    final rows = await _client
        .from('payments')
        .select(
            'id, kind, plan_code, period, credits, amount_xof, status, created_at')
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map(PaymentRecord.fromJson).toList();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('payments', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details is Map ? e.details as Map : const {};
      throw BillingException(switch (d['error']) {
        'provider_not_configured' =>
          'Le paiement n’est pas encore ouvert. Réessayez bientôt.',
        'too_many_pending' =>
          'Vous avez déjà plusieurs paiements en attente. Terminez-les ou patientez quelques minutes.',
        'feature_disabled' => 'Les achats sont momentanément indisponibles.',
        'provider_error' =>
          'L’opérateur de paiement n’a pas répondu. Réessayez dans un instant.',
        'invalid_plan' ||
        'invalid_quantity' ||
        'invalid_product' =>
          'Offre indisponible.',
        _ => 'Le paiement n’a pas pu démarrer. Réessayez.',
      });
    }
  }

  /// Crée le paiement côté serveur (prix calculé par le serveur) et renvoie (id, lien de paiement).
  Future<({String paymentId, String paymentUrl})> checkoutPlan(String planCode,
      {required bool annual}) async {
    final d = await _call({
      'action': 'checkout',
      'product': 'subscription',
      'plan_code': planCode,
      'period': annual ? 'annual' : 'monthly'
    });
    return (
      paymentId: d['payment_id'] as String,
      paymentUrl: d['payment_url'] as String
    );
  }

  Future<({String paymentId, String paymentUrl})> checkoutCredits(
      int quantity) async {
    final d = await _call(
        {'action': 'checkout', 'product': 'credits', 'quantity': quantity});
    return (
      paymentId: d['payment_id'] as String,
      paymentUrl: d['payment_url'] as String
    );
  }

  /// Statut confirmé par le serveur après vérification auprès de l'opérateur.
  Future<String> status(String paymentId) async =>
      (await _call({'action': 'status', 'payment_id': paymentId}))['status']
          as String;
}

final billingRepositoryProvider = Provider<BillingRepository>(
    (ref) => BillingRepository(ref.watch(supabaseClientProvider)));

final entitlementsProvider = FutureProvider.autoDispose<Entitlements>(
    (ref) => ref.watch(billingRepositoryProvider).entitlements());

final paymentsProvider = FutureProvider.autoDispose<List<PaymentRecord>>(
    (ref) => ref.watch(billingRepositoryProvider).payments());
