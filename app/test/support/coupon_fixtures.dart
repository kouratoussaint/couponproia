// Coupons de test (données fictives, structure réelle).
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';

final fixtureNow = DateTime.now();

Coupon fixtureCoupon(
  String id, {
  String category = 'prudent',
  String risk = 'prudent',
  double odd = 2.0,
  double prob = 0.4,
  String status = 'published',
  String? result,
  Duration kickoffIn = const Duration(hours: 5),
  Duration publishedAgo = const Duration(hours: 1),
  int selections = 2,
}) {
  final kickoff = fixtureNow.add(kickoffIn);
  return Coupon(
    id: id,
    category: category,
    title: 'Coupon $id',
    description: 'd',
    riskLevel: risk,
    totalOdd: odd,
    combinedProbability: prob,
    status: status,
    publishAt: fixtureNow.subtract(publishedAgo),
    publishedAt: fixtureNow.subtract(publishedAgo),
    firstKickoffAt: kickoff,
    lastKickoffAt: kickoff,
    engineVersion: 'poisson-1.1',
    dataSource: 'API-Football',
    summary: '',
    vigilance: const [],
    createdAt: fixtureNow.subtract(publishedAgo),
    result: result,
    selections: [
      for (var i = 0; i < selections; i++)
        CouponSelection.fromJson({
          'position': i + 1,
          'selection_key': '1X2.HOME',
          'odd': 1.5,
          'odds_captured_at': fixtureNow.toUtc().toIso8601String(),
          'model_probability': 0.6,
          'reliability': 'bonne',
          'justification': 'j',
          'match': {
            'id': i + 1,
            'kickoff_at': kickoff.toUtc().toIso8601String(),
            'status': 'scheduled',
            'home': {'name': 'Alpha'},
            'away': {'name': 'Beta'},
            'competition': {'name': 'Ligue'},
          },
        }),
    ],
  );
}

final fixtureCoupons = [
  fixtureCoupon('a', odd: 1.8, prob: 0.55, kickoffIn: const Duration(hours: 8)),
  fixtureCoupon('b',
      risk: 'audacieux',
      category: 'cote_elevee',
      odd: 9.5,
      prob: 0.1,
      kickoffIn: const Duration(hours: 2)),
  fixtureCoupon('c',
      odd: 3.2,
      result: 'won',
      kickoffIn: const Duration(days: -2),
      publishedAgo: const Duration(days: 2)),
  fixtureCoupon('d',
      odd: 4.1,
      result: 'lost',
      risk: 'equilibre',
      kickoffIn: const Duration(days: -10),
      publishedAgo: const Duration(days: 10)),
  fixtureCoupon('w',
      status: 'withdrawn',
      kickoffIn: const Duration(hours: 4),
      publishedAgo: const Duration(hours: 3)),
];
