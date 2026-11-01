// Lot 16 : simulateur de mise, carnet de paris, alertes de cote, transparence.
import 'package:coupon_pro_ia/core/providers.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_watch.dart';
import 'package:coupon_pro_ia/features/journal/data/journal_repository.dart';
import 'package:coupon_pro_ia/features/journal/presentation/journal_screen.dart';
import 'package:coupon_pro_ia/features/performance/performance_screen.dart';
import 'package:coupon_pro_ia/features/simulator/data/stake_math.dart';
import 'package:coupon_pro_ia/features/simulator/presentation/sim_entries.dart';
import 'package:coupon_pro_ia/features/simulator/presentation/stake_simulator_sheet.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';

const _nbsp = ' ';

SimLeg _leg(int id, double odd, {double? current, double? p}) => SimLeg(
    matchId: id,
    key: '1X2.HOME',
    matchLabel: 'M$id',
    pick: 'Victoire',
    odd: odd,
    currentOdd: current,
    probability: p);

JournalEntry _entry(String id, int stake, double odd, String? result,
        {DateTime? at, double? settled}) =>
    JournalEntry.fromJson({
      'id': id,
      'source_type': 'coupon',
      'source_id': 'c',
      'title': 'Coupon $id',
      'stake': stake,
      'total_odd': odd,
      'legs': [
        {
          'match_id': 1,
          'key': '1X2.HOME',
          'odd': odd,
          'label': 'Victoire A',
          'match': 'A – B'
        }
      ],
      'placed_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'first_kickoff_at': DateTime.now().toUtc().toIso8601String(),
      'result': result,
      'settled_odd': settled,
    });

void main() {
  group('calculs du simulateur', () {
    test('retour, net, prélèvement sur le bénéfice', () {
      final o = simulate(1000, 2.25);
      expect(o.payout, 2250);
      expect(o.net, 1250);
      final t = simulate(1000, 2.25, withholdingPercent: 20);
      expect(t.withholding, 250);
      expect(t.payout, 2000);
      expect(t.net, 1000);
    });

    test('valeur moyenne estimée : p × retour − mise', () {
      expect(expectedValue(1000, 2.0, 0.45), -100);
      expect(expectedValue(1000, 2.5, 0.5), 250);
    });

    test('coupon : cote actuelle, annulation, probabilité combinée', () {
      final input = SimInput(
          title: 'T',
          sourceType: 'lab',
          legs: [_leg(1, 1.5, current: 1.35, p: 0.6), _leg(2, 2.0, p: 0.5)]);
      expect(input.odd, 3.0);
      expect(input.currentOdd, 2.7);
      expect(input.oddWithoutLeg(0), 2.0);
      expect(input.estimatedProbability, closeTo(0.3, 1e-9));
      final unknown = SimInput(
          title: 'T',
          sourceType: 'lab',
          legs: [_leg(1, 1.5), _leg(2, 2.0, p: 0.5)]);
      expect(unknown.estimatedProbability, isNull);
      expect(unknown.currentOdd, isNull);
    });

    test('montants, saisie, mises comparées', () {
      expect(money(12500), '12${_nbsp}500 FCFA');
      expect(signedMoney(-1000), '−1${_nbsp}000 FCFA');
      expect(signedMoney(250), '+250 FCFA');
      expect(parseStake('2 500'), 2500);
      expect(parseStake('0'), isNull);
      expect(parseStake('abc'), isNull);
      expect(comparisonStakes(1000), [500, 1000, 2000, 5000, 10000]);
      expect(comparisonStakes(3000), [500, 1000, 2000, 3000, 5000, 10000]);
    });

    test('coupon de la plateforme : cotes actuelles reprises par sélection',
        () {
      final c = fixtureCoupon('x', odd: 2.25);
      final input = couponSim(c, {'1:1X2.HOME': 1.2});
      expect(input.odd, 2.25);
      expect(input.legs.first.currentOdd, 1.2);
      expect(input.currentOdd, 1.8);
      expect(input.sourceType, 'coupon');
    });
  });

  group('carnet de paris', () {
    test('retour et net selon le résultat', () {
      expect(_entry('a', 1000, 2.1, 'won', settled: 2.1).net, 1100);
      expect(_entry('b', 1000, 2.1, 'lost').net, -1000);
      expect(_entry('c', 1000, 2.1, 'void').net, 0);
      expect(_entry('d', 1000, 2.1, null).net, 0);
      expect(_entry('d', 1000, 2.1, null).potential, 2100);
    });

    test('bilan : misé, retourné, en attente', () {
      final t = JournalTotals.of([
        _entry('a', 1000, 2.0, 'won', settled: 2.0),
        _entry('b', 1000, 3.0, 'lost'),
        _entry('c', 500, 2.0, null),
      ]);
      expect(t.staked, 2500);
      expect(t.returned, 2000);
      expect(t.pending, 1);
      expect(t.net, 0);
    });

    test('regroupement par mois, du plus récent au plus ancien', () {
      final months = byMonth([
        _entry('a', 1, 2, null, at: DateTime(2026, 10, 3)),
        _entry('b', 1, 2, null, at: DateTime(2026, 11, 1)),
      ]);
      expect(months.keys.toList(), ['2026-11', '2026-10']);
      expect(monthLabel('2026-11'), 'Novembre 2026');
    });

    testWidgets('écran : bilan du mois et budget', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          journalProvider.overrideWith((ref) async => [
                _entry('a', 5000, 2.0, 'won', settled: 2.0),
                _entry('b', 4000, 1.8, null),
              ]),
          stakeLimitsProvider.overrideWith(
              (ref) async => const StakeLimits(monthlyBudget: 10000)),
          publicSettingsProvider.overrideWith((ref) async => {}),
        ],
        child: const MaterialApp(home: JournalScreen()),
      ));
      await tester.pumpAndSettle();
      expect(
          find.textContaining(
              '9${_nbsp}000 FCFA sur 10${_nbsp}000 FCFA (90 %)'),
          findsOneWidget);
      expect(find.text('Coupon a'), findsOneWidget);
      expect(find.textContaining('1 pari en attente'), findsOneWidget);
    });
  });

  group('simulateur (feuille)', () {
    Widget sheet(SimInput input, {StakeLimits limits = const StakeLimits()}) =>
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => null),
            stakeLimitsProvider.overrideWith((ref) async => limits),
            publicSettingsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp(
              home: Scaffold(body: StakeSimulatorSheet(choices: [input]))),
        );

    final input = SimInput(
        title: 'Coupon du jour',
        sourceType: 'coupon',
        totalOdd: 2.25,
        probability: 0.4,
        legs: [_leg(1, 1.5, p: 0.6), _leg(2, 1.5, p: 0.66)]);

    testWidgets('retour potentiel, lecture du modèle, mises comparées',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(sheet(input));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sim-payout')), findsOneWidget);
      expect(find.text('2${_nbsp}250 FCFA'), findsOneWidget);
      expect(find.textContaining('environ 40 passeraient'), findsOneWidget);
      expect(find.textContaining('−100 FCFA'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, '5${_nbsp}000'));
      await tester.pumpAndSettle();
      expect(find.text('11${_nbsp}250 FCFA'), findsOneWidget);
      for (final banned in ['sûr', 'garanti', 'assuré', 'gain']) {
        expect(find.textContaining(banned), findsNothing);
      }
    });

    testWidgets('plafond par pari rappelé', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          sheet(input, limits: const StakeLimits(stakeLimit: 2000)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Au-dessus de votre plafond'), findsNothing);
      await tester.tap(find.widgetWithText(ActionChip, '5${_nbsp}000'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Au-dessus de votre plafond'), findsOneWidget);
    });
  });

  group('alertes et transparence', () {
    test('variation de la cote totale', () {
      expect(totalOddsMove([(published: 2.0, current: null)]), isNull);
      expect(totalOddsMove([(published: 2.0, current: 1.7)]),
          closeTo(-0.15, 1e-9));
      expect(oddsMoveThreshold({'alerts.odds_move_percent': 15}), 0.15);
      expect(oddsMoveThreshold(null), 0.1);
    });

    testWidgets('résultat à mise fixe et calibration', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [publicSettingsProvider.overrideWith((ref) async => {})],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [
                FixedStakeCard(p: {
                  'settled': 10,
                  'returned': 12.5,
                  'theoretical_return': 0.25,
                  'by_category': [
                    {'key': 'prudent', 'settled': 4, 'returned': 3.2}
                  ],
                }),
                CalibrationChart(rows: [
                  {
                    'bucket': 0.6,
                    'selections': 12,
                    'predicted': 0.64,
                    'observed': 0.58
                  }
                ]),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('+2${_nbsp}500 FCFA'), findsOneWidget);
      expect(find.text('−800 FCFA'), findsOneWidget);
      expect(find.text('60–70 %'), findsOneWidget);
      expect(find.textContaining('peu de données'), findsOneWidget);
    });
  });
}
