// Cohérence avec l'analyse IA et modification d'un coupon par le super administrateur.
import 'package:coupon_pro_ia/features/analysis/data/analysis_models.dart';
import 'package:coupon_pro_ia/features/analysis/data/analysis_repository.dart';
import 'package:coupon_pro_ia/features/coupons/data/ai_consistency.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_repository.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_edit_screen.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';
import 'support/match_fixtures.dart';

OddsLine _odd(String market, String outcome, double median) =>
    OddsLine.fromJson({
      'market_code': market,
      'outcome_code': outcome,
      'line': null,
      'odd_median': median,
      'odd_best': median + 0.05,
      'bookmakers_count': 8,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    });

void main() {
  test('règle de cohérence (mêmes cas que le serveur)', () {
    expect(aiContradictions('DC.1X', ['1X2.AWAY']), ['1X2.AWAY']);
    expect(aiContradictions('DC.X2', ['1X2.AWAY']), isEmpty);
    expect(aiContradictions('DC.12', ['1X2.AWAY']), isEmpty);
    expect(aiContradictions('OU.OVER.2.5', ['1X2.AWAY']), isEmpty);
    expect(aiContradictions('OU.UNDER.2.5', ['OU.OVER.2.5']), ['OU.OVER.2.5']);
    expect(compatibleWithPick('OU.OVER.1.5', 'OU.OVER.2.5'), isTrue);
    expect(compatibleWithPick('BTTS.NO', 'BTTS.YES'), isFalse);
  });

  testWidgets('édition : pronostic IA affiché, sélection contraire signalée',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Coupon à valider : « Nul ou Beta » alors que l'IA retient la victoire d'Alpha.
    final c = fixtureCoupon('c1',
        status: 'pending_review', keys: const ['DC.X2', '1X2.HOME']);
    final analysis = MatchAnalysis.fromJson(lilleLensAnalysisJson());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myPermissionsProvider.overrideWith((ref) async => {'coupons.edit'}),
        couponProvider.overrideWith((ref, id) async => c),
        latestOddsProvider.overrideWith((ref, id) async => [
              _odd('1X2', 'HOME', 2.1),
              _odd('1X2', 'AWAY', 3.4),
              _odd('DC', '1X', 1.35),
              _odd('DC', 'X2', 1.7),
            ]),
        currentAnalysisProvider
            .overrideWith((ref, id) => AsyncData(id == 1 ? analysis : null)),
      ],
      child: const MaterialApp(home: CouponEditScreen(couponId: 'c1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le coupon'), findsOneWidget);
    expect(
        find.textContaining('Pronostic IA : Victoire Alpha'), findsOneWidget);
    expect(find.text('Pas encore d’analyse IA pour ce match'), findsOneWidget);
    expect(
        find.textContaining('Contraire au pronostic de l’IA (Victoire Alpha)'),
        findsOneWidget);
    expect(find.textContaining('cote indicative 3,57'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Indiquez le motif de la modification.'), findsOneWidget);
  });
}
