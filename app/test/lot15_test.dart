// Lot 15 : coupon au format bookmaker, historique trié par dernière action, analyse offerte.
import 'package:coupon_pro_ia/features/coupons/data/bookmaker_format.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_phase.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_repository.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_detail_screen.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_tiles.dart';
import 'package:coupon_pro_ia/features/admin/presentation/featured_admin_screen.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';
import 'support/match_fixtures.dart';

void main() {
  group('format bookmaker', () {
    test('codes de pari usuels', () {
      expect(bookmakerPick('1X2.HOME'), '1');
      expect(bookmakerPick('1X2.DRAW'), 'X');
      expect(bookmakerPick('1X2.AWAY'), '2');
      expect(bookmakerPick('DC.1X'), '1X');
      expect(bookmakerPick('DC.X2'), 'X2');
      expect(bookmakerPick('OU.OVER.2.5'), 'Plus de 2,5 buts (Total Plus 2,5)');
      expect(
          bookmakerPick('OU.UNDER.3.5'), 'Moins de 3,5 buts (Total Moins 3,5)');
      expect(bookmakerPick('BTTS.YES'), 'Les deux marquent : Oui');
      expect(bookmakerPick('BTTS.NO'), 'Les deux marquent : Non');
    });

    test('texte complet : une ligne par match, cotes, mention 18+', () {
      final c = fixtureCoupon('b',
          title: 'Prudent · samedi',
          odd: 2.25,
          keys: const ['DC.1X', 'OU.OVER.2.5']);
      final text = bookmakerText(c.title, c.totalOdd, c.selections);
      final lines = text.split('\n');
      expect(lines.first, 'Coupon Pro IA · Prudent · samedi');
      expect(lines[1], contains('Alpha – Beta · 1X · cote 1,50'));
      expect(lines[2], contains('Gamma – Delta · Plus de 2,5 buts'));
      expect(text, contains('Cote totale indicative : 2,25'));
      expect(text, contains('18+'));
      for (final banned in ['sûr', 'garanti', 'assuré', 'gain']) {
        expect(text.toLowerCase(), isNot(contains(banned)));
      }
    });

    test('lien bookmaker : https obligatoire, nom requis', () {
      expect(BookmakerLink.fromSetting(null), isNull);
      expect(BookmakerLink.fromSetting({'name': 'X', 'url': 'http://a.com'}),
          isNull);
      expect(BookmakerLink.fromSetting({'name': '', 'url': 'https://a.com'}),
          isNull);
      final l = BookmakerLink.fromSetting(
          {'name': '1xBet', 'url': 'https://example.com/fr'});
      expect(l?.name, '1xBet');
      expect(l?.url.host, 'example.com');
    });
  });

  group('historique par dernière action', () {
    final now = DateTime.now();
    StatusChange sc(String from, String to, Duration ago) =>
        StatusChange(fromStatus: from, toStatus: to, at: now.subtract(ago));

    test('libellés de la dernière action', () {
      final validated = fixtureCoupon('v', status: 'ready', history: [
        sc('draft', 'pending_review', const Duration(hours: 3)),
        sc('pending_review', 'ready', const Duration(hours: 1)),
      ]);
      expect(lastAction(validated).label, 'Validé · publication programmée');
      final created = fixtureCoupon('c', status: 'pending_review', history: [
        sc('draft', 'pending_review', const Duration(minutes: 5)),
      ]);
      expect(lastAction(created).label, 'Créé · à valider');
      final published = fixtureCoupon('p');
      expect(lastAction(published).label, 'Publié');
    });

    test('tri du plus récent au plus ancien', () {
      final old = fixtureCoupon('old', publishedAgo: const Duration(days: 2));
      final created = fixtureCoupon('new',
          status: 'pending_review',
          publishedAgo: const Duration(days: 3),
          history: [sc('draft', 'pending_review', const Duration(minutes: 2))]);
      final ready = fixtureCoupon('ready',
          status: 'ready',
          publishedAgo: const Duration(days: 3),
          history: [sc('draft', 'ready', const Duration(hours: 4))]);
      final sorted = sortByLastAction([old, ready, created]);
      expect([for (final c in sorted) c.id], ['new', 'ready', 'old']);
    });
  });

  group('analyse offerte (console)', () {
    Widget screen(Set<String> perms, {FeaturedChoice? choice}) => ProviderScope(
          overrides: [
            myPermissionsProvider.overrideWith((ref) async => perms),
            featuredChoiceProvider.overrideWith((ref, day) async => choice),
            featuredAutoHourProvider.overrideWith((ref) async => 10),
            matchesOfDayProvider
                .overrideWith((ref, day) async => [lilleLens()]),
            market1x2OfDayProvider.overrideWith((ref, day) async => {}),
          ],
          child: const MaterialApp(home: FeaturedAdminScreen()),
        );

    testWidgets('réservé au super administrateur', (tester) async {
      await tester.pumpWidget(screen(const {}));
      await tester.pumpAndSettle();
      expect(
          find.text('Écran réservé au super administrateur'), findsOneWidget);
    });

    testWidgets('sans choix : heure automatique et bouton « Choisir »',
        (tester) async {
      await tester.pumpWidget(screen(const {'featured.manage'}));
      await tester.pumpAndSettle();
      expect(find.textContaining('l’application en choisira un à 10 h'),
          findsOneWidget);
      expect(find.text('10 h'), findsOneWidget);
      expect(find.text('Choisir'), findsOneWidget);
    });

    testWidgets('match choisi par l’équipe', (tester) async {
      await tester.pumpWidget(screen(const {
        'featured.manage'
      }, choice: (
        matchId: 5988,
        chosenAt: DateTime(2099, 10, 30, 8),
        manual: true
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lille – Lens'), findsWidgets);
      expect(find.textContaining('Choisi par l’équipe'), findsOneWidget);
      expect(find.text('Choisir'), findsNothing);
    });
  });

  group('liste et fiche coupon', () {
    testWidgets('risque toujours affiché et icône du type', (tester) async {
      final c = fixtureCoupon('p', title: 'Coupon prudent · samedi');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: CompactCouponTile(coupon: c, onTap: () {}))));
      expect(find.text('Coupon prudent'), findsOneWidget);
      expect(find.text('Prudent'), findsOneWidget); // étiquette de risque
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(categoryIcon('strategie'), Icons.bolt);
      expect(categoryIcon('inconnu'), Icons.receipt_long_outlined);
    });

    testWidgets('historique : action la plus récente en premier',
        (tester) async {
      final now = DateTime.now();
      final c = fixtureCoupon('h', history: [
        StatusChange(
            fromStatus: 'draft',
            toStatus: 'ready',
            at: now.subtract(const Duration(hours: 2))),
        StatusChange(
            fromStatus: 'ready',
            toStatus: 'published',
            at: now.subtract(const Duration(hours: 1))),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          couponProvider.overrideWith((ref, id) async => c),
          currentOddsProvider.overrideWith((ref, id) async => {}),
          myPermissionsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: const MaterialApp(home: CouponDetailScreen(couponId: 'h')),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Historique'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final published = tester.getTopLeft(find.text('Publié').last).dy;
      final ready = tester.getTopLeft(find.textContaining('Prêt').last).dy;
      expect(published, lessThan(ready));
    });
  });
}
