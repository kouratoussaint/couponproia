// Version 0.30.0 : widget Android (B5) et aide intégrée (D6).
import 'package:coupon_pro_ia/core/router/app_routes.dart';
import 'package:coupon_pro_ia/features/help/help_content.dart';
import 'package:coupon_pro_ia/features/help/help_screens.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_format.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:coupon_pro_ia/features/widget/home_widget_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';
import 'support/match_fixtures.dart';

void main() {
  group('aide', () {
    test('articles uniques, thèmes connus, sans promesse de résultat', () {
      final ids = {for (final a in helpArticles) a.id};
      expect(ids.length, helpArticles.length);
      final forbidden = RegExp(
          r'(^|[^a-zà-ÿ])(sûr(e|s|es)?|sûrement|garanti\w*|assuré\w*|certitudes?|imparables?|infaillibles?|sans risque|gains?)([^a-zà-ÿ]|$)',
          caseSensitive: false);
      for (final a in helpArticles) {
        expect(helpCategories, contains(a.category), reason: a.id);
        for (final b in [a.title, ...a.blocks]) {
          expect(forbidden.hasMatch(b), isFalse, reason: '${a.id} : $b');
        }
        if (a.action case (_, final route)) {
          expect(route.startsWith('/'), isTrue, reason: a.id);
        }
      }
      for (final c in helpCategories) {
        expect(helpArticles.any((a) => a.category == c), isTrue, reason: c);
      }
    });

    test('recherche : accents ignorés, titre d’abord', () {
      expect(searchHelp('credits').first.id, 'credits');
      expect(searchHelp('WIDGET').first.id, 'widget');
      expect(searchHelp('rembourse').map((a) => a.id), contains('marches'));
      expect(searchHelp('xyzxyz'), isEmpty);
      expect(searchHelp('a'), helpArticles, reason: '2 lettres minimum');
    });

    test('coûts réglés dans la console', () {
      expect(
          fillCosts('{analysis_cost} / {lab_cost} / {assistant_cost}',
              analysis: '1 crédit', lab: '2 crédits', assistant: '1 crédit'),
          '1 crédit / 2 crédits / 1 crédit');
    });

    testWidgets('article : coût à jour et thème', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          publicSettingsProvider.overrideWith(
              (ref) async => {'analysis.credit_cost': 2, 'lab.credit_cost': 1}),
        ],
        child: const MaterialApp(home: HelpArticleScreen(id: 'credits')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Les crédits IA'), findsOneWidget);
      expect(
          find.textContaining(
              'Analyse d’un match avec le forfait FREE : 2 crédits'),
          findsOneWidget);
      expect(find.textContaining('{'), findsNothing);
    });

    testWidgets('centre d’aide : thèmes puis recherche', (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: HelpScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Bien démarrer'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'carnet');
      await tester.pumpAndSettle();
      expect(find.text('Le carnet de paris'), findsOneWidget);
      expect(find.text('Bien démarrer'), findsNothing);
    });
  });

  group('widget Android', () {
    final now = DateTime.now();

    test('pas encore de coupon du jour', () {
      final s = widgetSnapshot(null, [lilleLens()], now);
      expect(s.title, 'Coupon du jour');
      expect(s.line1, contains('Pas encore publié'));
      expect(s.line2, '1 match aujourd’hui');
      expect(s.route, AppRoutes.coupons);
    });

    test('coupon à jouer, réservé, gagné', () {
      final c = fixtureCoupon('a', category: 'du_jour', odd: 2.45);
      final s = widgetSnapshot(
          c,
          [
            lilleLens(status: 'live'),
            lilleLens(),
          ],
          now);
      expect(s.odd, '2,45');
      expect(s.line1, startsWith('2 sélections · 1er match '));
      expect(s.line2, '2 matchs aujourd’hui · 1 en direct');
      expect(s.route, AppRoutes.couponDetailFor('a'));

      final won = fixtureCoupon('w',
          category: 'du_jour',
          odd: 2.45,
          result: 'won',
          settledAgo: const Duration(minutes: 10));
      final sw = widgetSnapshot(won, const [], now);
      expect(sw.title, 'Coupon du jour · Gagné');
      expect(sw.line1, startsWith('Payé le '));
    });

    test('coupon du jour d’aujourd’hui, même décidé', () {
      final today = fixtureCoupon('t', category: 'du_jour', result: 'lost');
      final other = fixtureCoupon('o', category: 'prudent');
      expect(widgetCoupon([other, today], now)?.id, 't');
      expect(widgetCoupon([other], now), isNull);
      expect(kickoffLabel(dateOnly(now).add(const Duration(hours: 18)), now),
          '18:00');
    });
  });
}
