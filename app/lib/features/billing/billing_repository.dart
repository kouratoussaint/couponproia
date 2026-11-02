import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../assistant/data/assistant_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

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
    this.promoCode,
    this.discountXof = 0,
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
        promoCode: j['promo_code'] as String?,
        discountXof: _i(j['discount_xof']),
      );

  final String id;
  final String kind;
  final String? planCode;
  final String? period;
  final int? credits;
  final int amountXof;
  final String status;
  final DateTime createdAt;
  final String? promoCode;
  final int discountXof;
}

/// Code promo vérifié par le serveur (affichage ; le serveur recalcule au paiement).
class PromoQuote {
  const PromoQuote({
    required this.code,
    required this.percentOff,
    this.appliesTo = 'all',
    this.planCodes = const [],
    this.description = '',
    this.endsAt,
  });

  factory PromoQuote.fromJson(Map<String, dynamic> j) => PromoQuote(
        code: j['code'] as String,
        percentOff: _i(j['percent_off']),
        appliesTo: j['applies_to'] as String? ?? 'all',
        planCodes: [
          for (final c in (j['plan_codes'] as List? ?? const [])) c as String
        ],
        description: j['description'] as String? ?? '',
        endsAt: j['ends_at'] == null
            ? null
            : DateTime.parse(j['ends_at'] as String).toLocal(),
      );

  final String code;
  final int percentOff;
  final String appliesTo;
  final List<String> planCodes;
  final String description;
  final DateTime? endsAt;

  bool appliesToPlan(String plan) =>
      appliesTo != 'credits' && (planCodes.isEmpty || planCodes.contains(plan));

  bool get appliesToCredits => appliesTo != 'subscription';

  /// Même arrondi que le serveur : réduction au multiple de 5 inférieur.
  int discounted(int amount) =>
      amount - ((amount * percentOff / 100) / 5).floor() * 5;
}

String promoReasonMessage(String? reason) => switch (reason) {
      'unknown' => tr('Ce code n’existe pas.'),
      'inactive' => tr('Ce code n’est plus actif.'),
      'not_started' => tr('Ce code n’est pas encore valable.'),
      'expired' => tr('Ce code a expiré.'),
      'exhausted' => tr('Ce code a atteint son nombre d’utilisations.'),
      'already_used' => tr('Vous avez déjà utilisé ce code.'),
      'not_applicable' => tr('Ce code ne s’applique pas à cette offre.'),
      _ => tr('Code non valable.'),
    };

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
            'id, kind, plan_code, period, credits, amount_xof, status, created_at, promo_code, discount_xof')
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
          tr('Le paiement n’est pas encore ouvert. Réessayez bientôt.'),
        'too_many_pending' => tr(
            'Vous avez déjà plusieurs paiements en attente. Terminez-les ou patientez quelques minutes.'),
        'feature_disabled' =>
          tr('Les achats sont momentanément indisponibles.'),
        'provider_error' => tr(
            'L’opérateur de paiement n’a pas répondu. Réessayez dans un instant.'),
        'invalid_promo' => promoReasonMessage(d['reason'] as String?),
        'invalid_plan' ||
        'invalid_quantity' ||
        'invalid_product' =>
          tr('Offre indisponible.'),
        _ => tr('Le paiement n’a pas pu démarrer. Réessayez.'),
      });
    }
  }

  /// Crée le paiement côté serveur (prix calculé par le serveur) et renvoie (id, lien de paiement).
  Future<({String paymentId, String paymentUrl})> checkoutPlan(String planCode,
      {required bool annual, String? promoCode}) async {
    final d = await _call({
      'action': 'checkout',
      'product': 'subscription',
      'plan_code': planCode,
      'period': annual ? 'annual' : 'monthly',
      if (promoCode != null) 'promo_code': promoCode,
    });
    return (
      paymentId: d['payment_id'] as String,
      paymentUrl: d['payment_url'] as String
    );
  }

  Future<({String paymentId, String paymentUrl})> checkoutCredits(int quantity,
      {String? promoCode}) async {
    final d = await _call({
      'action': 'checkout',
      'product': 'credits',
      'quantity': quantity,
      if (promoCode != null) 'promo_code': promoCode,
    });
    return (
      paymentId: d['payment_id'] as String,
      paymentUrl: d['payment_url'] as String
    );
  }

  /// Vérifie un code promo (portée et réduction) ; lève [BillingException] s'il n'est pas valable.
  Future<PromoQuote> checkPromo(String code) async {
    final r = Map<String, dynamic>.from(await _client
        .rpc('check_promo', params: {'p_code': code.trim()}) as Map);
    if (r['ok'] != true) {
      throw BillingException(promoReasonMessage(r['reason'] as String?));
    }
    return PromoQuote.fromJson(r);
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

/// Forfait payant qui se termine (3 jours) ou vient de se terminer (7 jours) : « Renouveler ».
class Renewal {
  const Renewal(
      {required this.planCode,
      required this.annual,
      required this.periodEnd,
      required this.ended});

  static Renewal? fromJson(Object? v) {
    if (v is! Map) return null;
    return Renewal(
      planCode: v['plan_code'] as String,
      annual: v['period'] == 'annual',
      periodEnd: DateTime.parse(v['period_end'] as String).toLocal(),
      ended: v['ended'] == true,
    );
  }

  final String planCode;
  final bool annual;
  final DateTime periodEnd;
  final bool ended;

  /// Écran Abonnement avec la proposition de renouvellement.
  String get route =>
      '/abonnement?renouveler=$planCode&periode=${annual ? 'annual' : 'monthly'}';
}

final renewalProvider = FutureProvider.autoDispose<Renewal?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client.auth.currentUser == null) return null;
  return Renewal.fromJson(await client.rpc('my_renewal'));
});
