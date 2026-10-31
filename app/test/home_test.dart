import 'package:coupon_pro_ia/features/assistant/data/assistant_models.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_repository.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_repository.dart';
import 'package:coupon_pro_ia/features/home/home_screen.dart';
import 'package:coupon_pro_ia/features/matches/data/insights_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/profile/data/profile_repository.dart';
import 'package:coupon_pro_ia/features/onboarding/data/preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/match_fixtures.dart';

Coupon _coupon(String id, String category,
        {String? result, required DateTime first}) =>
    Coupon.fromJson({
      'id': id,
      'category': category,
      'title': category == 'du_jour' ? 'Coupon du jour' : 'Coupon prudent',
      'description': '',
      'risk_level': 'equilibre',
      'total_odd': 3.12,
      'combined_probability': 0.31,
      'status': 'published',
      'publish_at': DateTime.now().toUtc().toIso8601String(),
      'published_at': DateTime.now().toUtc().toIso8601String(),
      'first_kickoff_at': first.toUtc().toIso8601String(),
      'last_kickoff_at': first.toUtc().toIso8601String(),
      'engine_version': 'poisson-1.1',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'result': result,
      'settled_at':
          result == null ? null : DateTime.now().toUtc().toIso8601String(),
    });

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('coupon du jour : celui publié aujourd’hui et encore ouvert', () {
    final now = DateTime.now();
    final c = couponOfTheDay([
      _coupon('a', 'prudent', first: now.add(const Duration(hours: 4))),
      _coupon('b', 'du_jour', first: now.add(const Duration(hours: 5))),
    ], now);
    expect(c?.id, 'b');
    expect(
        couponOfTheDay([
          _coupon('c', 'du_jour', first: now.subtract(const Duration(days: 2)))
        ], now),
        isNull);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('accueil complet sans débordement (texte ×$scale)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => null),
          myPreferencesProvider.overrideWith(
              (ref) async => UserPreferences(onboardedAt: DateTime(2026))),
          myCreditsProvider.overrideWith((ref) async => Credits.fromJson({
                'plan': 'FREE',
                'total': 2,
                'plan_credits': 2,
                'extra_credits': 0,
                'unlimited': false
              })),
          publishedCouponsProvider.overrideWith((ref) async => [
                _coupon('b', 'du_jour',
                    first: now.add(const Duration(hours: 5))),
                _coupon('w', 'prudent',
                    result: 'won',
                    first: now.subtract(const Duration(days: 1))),
                _coupon('l', 'prudent',
                    result: 'lost',
                    first: now.subtract(const Duration(days: 2))),
              ]),
          featuredMatchProvider.overrideWith((ref) async => 5988),
          matchProvider.overrideWith((ref, id) async => lilleLens()),
          matchesOfDayProvider.overrideWith((ref, day) async => [lilleLens()]),
          market1x2OfDayProvider.overrideWith((ref, day) async => {
                5988: const Market1x2(
                    matchId: 5988,
                    pHome: 0.35,
                    pDraw: 0.29,
                    pAway: 0.36,
                    bookmakers: 10)
              }),
        ],
        child: MaterialApp(
          home: const HomeScreen(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
        ),
      ));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      expect(find.text('CADEAU · ANALYSE OFFERTE DU JOUR'), findsOneWidget);
      expect(find.text('à jouer'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Voir le coupon'), 300,
          scrollable: list);
      expect(find.text('COUPON DU JOUR'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Marché : 1 · N · 2'), 300,
          scrollable: list);
      expect(find.text('35 · 29 · 36'), findsOneWidget);
      await tester.tap(find.text('Demain'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Derniers coupons'), 300,
          scrollable: list);
      await tester.scrollUntilVisible(
          find.textContaining('1 gagné · 1 perdu sur 2 réglés'), 300,
          scrollable: list);
      await tester.scrollUntilVisible(find.text('Perdu'), 300,
          scrollable: list);
      expect(find.text('Gagné'), findsOneWidget);
      // Les raccourcis viennent en dernier.
      await tester.scrollUntilVisible(find.text('Laboratoire'), 300,
          scrollable: list);
      expect(tester.takeException(), isNull);
    });
  }
}
