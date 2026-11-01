// Version 0.27.0 : dates sur les lignes de coupons et le carnet, couleurs du bouton
// « Analyser », coût en crédits affiché sur les boutons, nouveaux onglets.
import 'package:coupon_pro_ia/core/theme/solid_buttons.dart';
import 'package:coupon_pro_ia/features/analysis/presentation/analyze_access.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_models.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_repository.dart';
import 'package:coupon_pro_ia/features/assistant/presentation/assistant_hub_screen.dart';
import 'package:coupon_pro_ia/features/billing/credit_costs.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_phase.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_format.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';
import 'support/match_fixtures.dart';

Credits _credits(String plan, int total, {bool unlimited = false}) =>
    Credits.fromJson({
      'plan': plan,
      'total': total,
      'plan_credits': total,
      'extra_credits': 0,
      'unlimited': unlimited,
    });

Widget _button(Credits credits,
        {bool analyzed = false, Map<String, dynamic> settings = const {}}) =>
    ProviderScope(
      overrides: [
        myCreditsProvider.overrideWith((ref) async => credits),
        myPermissionsProvider.overrideWith((ref) async => <String>{}),
        featuredMatchProvider.overrideWith((ref) async => null),
        publicSettingsProvider.overrideWith((ref) async => settings),
        analyzedOfDayProvider.overrideWith(
            (ref, day) async => analyzed ? {lilleLens().id} : <int>{}),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Center(child: AnalyzeMatchButton(match: lilleLens())))),
    );

Color? _background(WidgetTester tester) {
  final button = tester.widget<ButtonStyleButton>(find.byWidgetPredicate(
      (w) => w is ButtonStyleButton && w.style?.backgroundColor != null));
  return button.style!.backgroundColor!.resolve(<WidgetState>{});
}

void main() {
  test('date complète : année et heure', () {
    expect(dateTimeLabel(DateTime(2026, 11, 1, 9, 5)), '01/11/2026 à 09:05');
  });

  test('coupon : publié le…, payé ou terminé le…', () {
    final toPlay = fixtureCoupon('a');
    expect(publishedLine(toPlay),
        'Publié le ${dateTimeLabel(toPlay.publishedAt!)}');
    final won = fixtureCoupon('b',
        result: 'won', settledAgo: const Duration(minutes: 30));
    expect(settledLine(won), startsWith('Payé le '));
    expect(settledLine(won), contains('/${won.settledAt!.year} à '));
    final lost = fixtureCoupon('c',
        result: 'lost', settledAgo: const Duration(minutes: 30));
    expect(settledLine(lost), startsWith('Terminé le '));
    final voided = fixtureCoupon('d',
        result: 'void', settledAgo: const Duration(minutes: 30));
    expect(settledLine(voided), startsWith('Terminé le '));
    expect(settledLine(fixtureCoupon('e', result: 'won')), isEmpty);
  });

  test('analyse : crédits suffisants pour le coût réglé', () {
    expect(canAnalyzeWith(_credits('FREE', 1), cost: 2), isFalse);
    expect(canAnalyzeWith(_credits('FREE', 2), cost: 2), isTrue);
    expect(canAnalyzeWith(_credits('FREE', 0), cost: 0), isTrue);
    expect(canAnalyzeWith(_credits('PRO', 0), cost: 5), isTrue);
  });

  test('libellés de crédits et onglets de l’Assistant IA', () {
    expect(creditsLabel(1), '1 crédit');
    expect(creditsLabel(3), '3 crédits');
    expect(analyzeLabel(0), 'Analyser');
    expect(analyzeLabel(2), 'Analyser · 2 crédits');
    expect(assistantTabFrom(null), 0);
    expect(assistantTabFrom('coupons'), 1);
    expect(assistantTabFrom('laboratoire'), 2);
    expect(paysCreditsAsFree(_credits('FREE', 0)), isTrue);
    expect(paysCreditsAsFree(_credits('STARTER', 0)), isFalse);
    expect(paysCreditsAsFree(_credits('FREE', 0, unlimited: true)), isFalse);
  });

  testWidgets('Analyser : vert plein avec le coût au forfait FREE',
      (tester) async {
    await tester.pumpWidget(
        _button(_credits('FREE', 3), settings: {'analysis.credit_cost': 2}));
    await tester.pumpAndSettle();
    expect(find.text('Analyser · 2 crédits'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    final ctx = tester.element(find.byType(AnalyzeMatchButton));
    expect(_background(tester), solidColors(ctx, SolidTone.green).bg);
  });

  testWidgets('Analyser : vert plein sans coût avec un forfait payant',
      (tester) async {
    await tester.pumpWidget(_button(_credits('STARTER', 0)));
    await tester.pumpAndSettle();
    expect(find.text('Analyser'), findsOneWidget);
  });

  testWidgets('Analyser : rouge avec cadenas sans droit', (tester) async {
    await tester.pumpWidget(_button(_credits('FREE', 0)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    final ctx = tester.element(find.byType(AnalyzeMatchButton));
    expect(_background(tester), solidColors(ctx, SolidTone.red).bg);
  });

  testWidgets('analyse déjà obtenue : orange plein « Voir l’analyse »',
      (tester) async {
    await tester.pumpWidget(_button(_credits('FREE', 0), analyzed: true));
    await tester.pumpAndSettle();
    expect(find.text('Voir l’analyse'), findsOneWidget);
    final ctx = tester.element(find.byType(AnalyzeMatchButton));
    expect(_background(tester), solidColors(ctx, SolidTone.orange).bg);
  });
}
