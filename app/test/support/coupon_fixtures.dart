// Coupons de test (données fictives, structure réelle des réponses du serveur).
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';

final fixtureNow = DateTime.now();

/// Une sélection : [result] null = non réglée ; [status] du match ; score facultatif.
typedef Sel = ({String? result, String status, int? hg, int? ag});

const Sel pendingSel = (result: null, status: 'scheduled', hg: null, ag: null);

Coupon fixtureCoupon(
  String id, {
  String category = 'prudent',
  String risk = 'prudent',
  String? title,
  double odd = 2.0,
  double prob = 0.4,
  String status = 'published',
  String? result,
  Duration kickoffIn = const Duration(hours: 5),
  Duration publishedAgo = const Duration(hours: 1),
  Duration? settledAgo,
  List<Sel> sels = const [pendingSel, pendingSel],
}) {
  final kickoff = fixtureNow.add(kickoffIn);
  return Coupon(
    id: id,
    category: category,
    title: title ?? '${categoryLabels[category]} · samedi',
    description: 'd',
    riskLevel: risk,
    totalOdd: odd,
    combinedProbability: prob,
    status: status,
    publishAt: fixtureNow.subtract(publishedAgo),
    publishedAt: fixtureNow.subtract(publishedAgo),
    firstKickoffAt: kickoff,
    lastKickoffAt: kickoff.add(const Duration(hours: 2)),
    engineVersion: 'poisson-1.1',
    dataSource: 'API-Football',
    summary: '',
    vigilance: const [],
    createdAt: fixtureNow.subtract(publishedAgo),
    result: result,
    settledOdd: result == 'won' ? odd : null,
    settledAt: settledAgo == null ? null : fixtureNow.subtract(settledAgo),
    selections: [
      for (var i = 0; i < sels.length; i++)
        CouponSelection.fromJson({
          'position': i + 1,
          'selection_key': '1X2.HOME',
          'odd': 1.5,
          'odds_captured_at': fixtureNow.toUtc().toIso8601String(),
          'model_probability': 0.6,
          'reliability': 'bonne',
          'justification': 'j',
          'result': sels[i].result,
          'match': {
            'id': i + 1,
            'kickoff_at':
                kickoff.add(Duration(hours: i)).toUtc().toIso8601String(),
            'status': sels[i].status,
            'home_goals': sels[i].hg,
            'away_goals': sels[i].ag,
            'home': {'name': i == 0 ? 'Alpha' : 'Gamma'},
            'away': {'name': i == 0 ? 'Beta' : 'Delta'},
            'competition': {'name': 'Ligue'},
          },
        }),
    ],
  );
}

/// Actifs : deux à jouer (dont le Coupon du jour), un en cours.
final fixtureActive = [
  fixtureCoupon('a',
      category: 'du_jour',
      title: 'Coupon du jour · samedi',
      odd: 2.53,
      prob: 0.41,
      kickoffIn: const Duration(hours: 5)),
  fixtureCoupon('b',
      odd: 1.62, prob: 0.61, kickoffIn: const Duration(hours: 2)),
  fixtureCoupon('l',
      category: 'equilibre',
      risk: 'equilibre',
      odd: 3.1,
      kickoffIn: const Duration(hours: -1),
      sels: const [
        (result: 'won', status: 'finished', hg: 2, ag: 0),
        pendingSel,
      ]),
];

/// Décidés : un gagné il y a 2 jours, un perdu aujourd'hui, un perdu il y a 10 jours.
final fixtureDecided = [
  fixtureCoupon('d1',
      category: 'cote_elevee',
      risk: 'audacieux',
      odd: 20.66,
      result: 'lost',
      kickoffIn: const Duration(hours: -6),
      settledAgo: Duration.zero,
      sels: const [
        (result: 'lost', status: 'finished', hg: 0, ag: 2),
        pendingSel,
      ]),
  fixtureCoupon('w',
      odd: 3.2,
      result: 'won',
      kickoffIn: const Duration(days: -2),
      settledAgo: const Duration(days: 2),
      sels: const [
        (result: 'won', status: 'finished', hg: 1, ag: 0),
        (result: 'won', status: 'finished', hg: 3, ag: 1),
      ]),
  fixtureCoupon('old',
      category: 'equilibre',
      risk: 'equilibre',
      odd: 4.1,
      result: 'lost',
      kickoffIn: const Duration(days: -10),
      settledAgo: const Duration(days: 10),
      sels: const [
        (result: 'lost', status: 'finished', hg: 1, ag: 1),
        (result: 'won', status: 'finished', hg: 2, ag: 0),
      ]),
];

final fixtureWithdrawn = [
  fixtureCoupon('x', status: 'withdrawn', kickoffIn: const Duration(hours: 4)),
];

/// Tous, pour les écrans qui lisent la liste complète.
final fixtureCoupons = [
  ...fixtureActive,
  ...fixtureDecided,
  ...fixtureWithdrawn
];
