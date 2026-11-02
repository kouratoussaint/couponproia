// Version 0.29.0 : nouveaux marchés (D2), recherche (B4), rapport hebdomadaire (C5).
import 'package:coupon_pro_ia/features/analysis/data/analysis_format.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_repository.dart';
import 'package:coupon_pro_ia/features/community/data/community_repository.dart';
import 'package:coupon_pro_ia/features/coupons/data/ai_consistency.dart';
import 'package:coupon_pro_ia/features/coupons/data/bookmaker_format.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_repository.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_format.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/notifications/data/notifications_repository.dart';
import 'package:coupon_pro_ia/features/search/search_repository.dart';
import 'package:coupon_pro_ia/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';

OddsLine _odd(String m, String o, [double? line]) => OddsLine(
    marketCode: m,
    outcomeCode: o,
    line: line,
    median: 2,
    best: 2.1,
    bookmakers: 5,
    capturedAt: DateTime(2026, 11, 2));

void main() {
  test('nouveaux marchés : libellés, cotes, bookmaker', () {
    expect(outcomeKeyLabel('DNB.HOME', 'Lille', 'Lens'),
        'Lille (remboursé si nul)');
    expect(outcomeKeyLabel('TTA.OVER.0.5', 'Lille', 'Lens'),
        'Lens : plus de 0,5 but');
    expect(outcomeKeyLabel('TTH.UNDER.2.5', 'Lille', 'Lens'),
        'Lille : moins de 2,5 buts');
    expect(outcomeKeyLabel('TTH.OVER.1.5', 'Lille', 'Lens'),
        'Lille : plus de 1,5 buts');
    expect(outcomeLabel(_odd('DNB', 'AWAY')), '2');
    expect(outcomeLabel(_odd('TTH', 'OVER', 1.5)), 'Plus de 1,5');
    final grouped = oddsByMarket([
      _odd('TTA', 'OVER', 0.5),
      _odd('DNB', 'HOME'),
      _odd('1X2', 'HOME'),
    ]);
    expect(grouped.keys, ['1X2', 'DNB', 'TTA']);
    expect(marketTitles['TTH'], 'Buts de l’équipe à domicile');
    final c = fixtureCoupon('x', keys: ['DNB.AWAY']);
    expect(
        bookmakerText('C', 2, c.selections), contains('Remboursé si nul : 2'));
  });

  test('cohérence IA : remboursé si nul dans la famille du résultat', () {
    expect(compatibleWithPick('DNB.HOME', '1X2.HOME'), isTrue);
    expect(compatibleWithPick('DNB.HOME', 'DC.1X'), isTrue);
    expect(compatibleWithPick('DNB.HOME', '1X2.AWAY'), isFalse);
    expect(compatibleWithPick('TTH.OVER.0.5', '1X2.AWAY'), isTrue);
  });

  test('recherche : accents, casse, début du nom d’abord', () {
    const teams = [
      TeamRef(id: 1, name: 'Paris Saint-Germain'),
      TeamRef(id: 2, name: 'Saint-Étienne'),
      TeamRef(id: 3, name: 'Lens'),
    ];
    expect(searchTeams(teams, 'e'), isEmpty, reason: '2 lettres minimum');
    expect([for (final t in searchTeams(teams, 'saint')) t.id], [2, 1]);
    expect([for (final t in searchTeams(teams, 'ETIENNE')) t.id], [2]);
    expect(matchesText('Ligue 1', 'ligue'), isTrue);
    final coupons = [
      fixtureCoupon('a'),
      fixtureCoupon('b', title: 'Spécial samedi'),
    ];
    expect(searchCoupons(coupons, 'gamma').length, 2);
    expect(searchCoupons(coupons, 'special').single.id, 'b');
  });

  test('rapport hebdomadaire : désactivé par défaut, lu depuis la base', () {
    expect(const NotificationPrefs().weeklyEmail, isFalse);
    expect(
        NotificationPrefs.fromJson({'weekly_email': true}).weeklyEmail, isTrue);
    expect(NotificationPrefs.columns, contains('weekly_email'));
  });

  testWidgets('écran de recherche : équipes, matchs, coupons', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        allTeamsProvider.overrideWith((ref) async => const [
              TeamRef(id: 7, name: 'Gamma FC'),
              TeamRef(id: 8, name: 'Lens'),
            ]),
        competitionsProvider
            .overrideWith((ref) async => const <CompetitionRef>[]),
        activeCouponsProvider.overrideWith((ref) async => [fixtureCoupon('a')]),
        savedCouponsProvider.overrideWith((ref) async => const []),
        favoriteTeamsProvider
            .overrideWith((ref) async => const <int, String>{}),
        teamMatchesProvider.overrideWith((ref, ids) async => const []),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Que cherchez-vous ?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'gamma');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Équipes · 1'), findsOneWidget);
    expect(find.text('Gamma FC'), findsOneWidget);
    expect(find.text('Coupons IA · 1'), findsOneWidget);
    expect(find.byTooltip('Suivre cette équipe'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
  });
}
