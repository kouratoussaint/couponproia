import 'package:coupon_pro_ia/features/lab/data/lab_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

OddsLine _odd(String market, String outcome, [double? line]) => OddsLine(
      marketCode: market,
      outcomeCode: outcome,
      line: line,
      median: 1.8,
      best: 1.9,
      bookmakers: 5,
      capturedAt: DateTime(2026, 10, 31),
    );

void main() {
  test('clé d’issue identique à celle du serveur', () {
    expect(oddsKey(_odd('1X2', 'HOME')), '1X2.HOME');
    expect(oddsKey(_odd('OU', 'OVER', 2.5)), 'OU.OVER.2.5');
    expect(oddsKey(_odd('OU', 'UNDER', 1)), 'OU.UNDER.1');
  });

  test('coupon manuel : une sélection par match, retrait au second toucher',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(manualCouponProvider.notifier);
    const a = ManualPick(
        matchId: 1, key: '1X2.HOME', matchLabel: 'A – B', label: '1', odd: 1.8);
    const a2 = ManualPick(
        matchId: 1, key: 'DC.1X', matchLabel: 'A – B', label: '1X', odd: 1.25);
    const b = ManualPick(
        matchId: 2, key: '1X2.AWAY', matchLabel: 'C – D', label: '2', odd: 2.5);
    n.toggle(a);
    n.toggle(b);
    n.toggle(a2);
    expect(container.read(manualCouponProvider).map((p) => p.key),
        ['1X2.AWAY', 'DC.1X']);
    expect(indicativeOdd(container.read(manualCouponProvider)),
        closeTo(3.125, 1e-9));
    n.toggle(a2);
    expect(container.read(manualCouponProvider).map((p) => p.matchId), [2]);
  });

  test('simulation lue avec son avertissement', () {
    final s = CouponSimulation.fromJson({
      'label': 'Simulation : … pas un résultat réel',
      'runs': 1000,
      'probability_all_correct': 0.336,
      'distribution': [0.024, 0.188, 0.452, 0.336],
      'expected_correct': 2.1,
      'simulated_wins': 341,
      'wins_interval': [307, 365],
      'model_return_per_unit': 1.512,
    });
    expect(s.label, contains('pas un résultat réel'));
    expect(s.distribution.length, 4);
    expect(s.winsHigh, 365);
  });
}
