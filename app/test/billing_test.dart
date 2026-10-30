import 'package:coupon_pro_ia/features/billing/billing_repository.dart';
import 'package:coupon_pro_ia/features/billing/billing_screen.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final starter = PlanOffer.fromJson({
    'code': 'STARTER',
    'name': 'STARTER',
    'monthly_xof': 2000,
    'ai_credits': 10,
    'features': {'coupon_categories': 'all', 'match_analyses_per_day': 20},
  });

  test('prix annuel identique au calcul du serveur', () {
    expect(starter.priceFor(annual: false, discountPercent: 15), 2000);
    expect(starter.priceFor(annual: true, discountPercent: 15), 20400);
    expect(starter.priceFor(annual: true, discountPercent: 0), 24000);
  });

  test('avantages du forfait lus depuis les réglages', () {
    expect(starter.allCoupons, isTrue);
    expect(starter.analysesPerDay, 20);
    final free = PlanOffer.fromJson({
      'code': 'FREE',
      'name': 'FREE',
      'monthly_xof': 0,
      'ai_credits': 2,
      'features': {
        'coupon_categories': ['du_jour'],
        'match_analyses_per_day': 3
      },
    });
    expect(free.allCoupons, isFalse);
  });

  test('droits de l’utilisateur', () {
    final e = Entitlements.fromJson({
      'plan': 'PRO_TIPSTER',
      'period_end': '2026-12-01T00:00:00Z',
      'features': {'coupon_categories': 'all'},
      'credits': {
        'plan': 'PRO_TIPSTER',
        'total': 55,
        'plan_credits': 50,
        'extra_credits': 5,
        'unlimited': false
      },
    });
    expect(e.plan, 'PRO_TIPSTER');
    expect(e.allCoupons, isTrue);
    expect(e.credits.total, 55);
    expect(e.periodEnd, isNotNull);
  });

  test('montants en FCFA', () {
    expect(fcfa(500), '500 FCFA');
    expect(fcfa(20400), '20 400 FCFA');
    expect(fcfa(120000), '120 000 FCFA');
  });

  test('coupon réservé : aucune sélection ni analyse', () {
    final c = Coupon.fromJson({
      'id': 'x',
      'category': 'prudent',
      'title': 'Coupon prudent',
      'description': '',
      'risk_level': 'prudent',
      'total_odd': 2.1,
      'combined_probability': 0.5,
      'status': 'published',
      'publish_at': '2026-10-30T07:00:00Z',
      'first_kickoff_at': '2026-10-31T15:00:00Z',
      'last_kickoff_at': '2026-10-31T19:00:00Z',
      'engine_version': 'poisson-1.1',
      'created_at': '2026-10-30T06:00:00Z',
      'analysis': {'source': 'ia'},
      'locked': true,
    });
    expect(c.locked, isTrue);
    expect(c.selections, isEmpty);
    expect(c.summary, isEmpty);
  });
}
