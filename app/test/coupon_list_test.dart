import 'package:coupon_pro_ia/features/coupons/coupons_screen.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_query.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_repository.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_actions.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_widgets.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';

final _now = fixtureNow;
final _all = fixtureCoupons;

Widget _screen(Set<String> perms) => ProviderScope(
      overrides: [
        publishedCouponsProvider.overrideWith((ref) async => _all),
        featureFlagsProvider.overrideWith((ref) async => const {}),
        myPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: CouponsScreen()),
    );

List<String> _ids(List<Coupon> l) => [for (final c in l) c.id];

void main() {
  group('tri et filtres', () {
    test(
        'par défaut : en jeu par coup d’envoi, historique récent d’abord, retirés en historique',
        () {
      final r = const CouponQuery().apply(_all, now: _now);
      expect(_ids(r.open), ['b', 'a']);
      expect(_ids(r.past), ['w', 'c', 'd']);
    });

    test('cote la plus haute, probabilité, sélections', () {
      expect(
          _ids(const CouponQuery(sort: CouponSort.oddDesc)
              .apply(_all, now: _now)
              .open),
          ['b', 'a']);
      expect(
          _ids(const CouponQuery(sort: CouponSort.probabilityDesc)
              .apply(_all, now: _now)
              .open),
          ['a', 'b']);
    });

    test('filtres : état, risque, cote, période, catégorie', () {
      List<String> ids(CouponQuery q, {String? category}) {
        final r = q.apply(_all, category: category, now: _now);
        return [..._ids(r.open), ..._ids(r.past)];
      }

      expect(ids(const CouponQuery(states: {CouponState.lost})), ['d']);
      expect(ids(const CouponQuery(states: {CouponState.withdrawn})), ['w']);
      expect(ids(const CouponQuery(risks: {'audacieux'})), ['b']);
      expect(ids(const CouponQuery(oddRange: OddRange.high)), ['b']);
      expect(ids(const CouponQuery(oddRange: OddRange.low)), ['a', 'w']);
      expect(ids(const CouponQuery(days: 7)), ['b', 'a', 'w', 'c']);
      expect(ids(const CouponQuery(), category: 'cote_elevee'), ['b']);
      expect(
          const CouponQuery(
                  states: {CouponState.won}, oddRange: OddRange.mid, days: 7)
              .activeFilters,
          3);
    });
  });

  test('date : jamais affichée deux fois', () {
    final now = DateTime(2026, 10, 31, 12);
    expect(couponDateLabel(DateTime(2026, 10, 29, 17, 1), now),
        isNot(contains('29/10 29/10')));
    expect(couponDateLabel(DateTime(2026, 10, 31, 19), now),
        'Aujourd’hui 31/10 · 19:00');
  });

  test('texte partagé : sélections, cote, mention d’estimation', () {
    final t = couponShareText(_all.first);
    expect(t, contains('Alpha – Beta'));
    expect(t, contains('Cote totale 1,80'));
    expect(t, contains('aucune certitude'));
    for (final w in ['sûr', 'garanti', 'assuré']) {
      expect(t.toLowerCase(), isNot(contains(w)));
    }
  });

  testWidgets(
      'écran : retiré grisé, appui long, suppression réservée à l’équipe',
      (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_screen(const {}));
    await tester.pumpAndSettle();
    expect(find.text('5 coupons'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Coupon w'), matching: find.byType(ColorFiltered)),
        findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Coupon a'), matching: find.byType(ColorFiltered)),
        findsNothing);
    expect(find.textContaining('coupons retirés affichés'), findsNothing);

    await tester.longPress(find.text('Coupon a'));
    await tester.pumpAndSettle();
    expect(find.text('Partager en texte'), findsOneWidget);
    expect(find.text('Supprimer définitivement'), findsNothing);
  });

  testWidgets('équipe : suppression des retirés proposée', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    await tester
        .pumpWidget(_screen(const {'coupons.publish', 'generation.manage'}));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer le coupon retiré affiché'), findsOneWidget);

    await tester.longPress(find.text('Coupon w'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer définitivement'), findsOneWidget);
    expect(find.text('Retirer ce coupon'), findsNothing);
  });

  testWidgets('filtrer : panneau, application, compteur', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_screen(const {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtrer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perdus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(find.text('1 coupon'), findsOneWidget);
    expect(find.text('Coupon d'), findsOneWidget);
    expect(find.text('Coupon a'), findsNothing);
  });

  testWidgets('écran : texte ×1,6 sans débordement', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 3200 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        publishedCouponsProvider.overrideWith((ref) async => _all),
        featureFlagsProvider.overrideWith((ref) async => const {}),
        myPermissionsProvider
            .overrideWith((ref) async => const {'coupons.publish'}),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: const CouponsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
