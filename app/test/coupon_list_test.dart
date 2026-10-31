import 'package:coupon_pro_ia/features/coupons/coupons_screen.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_phase.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_repository.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_actions.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_widgets.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';

final _now = fixtureNow;

Coupon _byId(String id) => fixtureCoupons.firstWhere((c) => c.id == id);

List<String> _ids(Iterable<Coupon> l) => [for (final c in l) c.id];

Widget _screen(Set<String> perms, {double scale = 1}) => ProviderScope(
      overrides: [
        activeCouponsProvider.overrideWith((ref) async => fixtureActive),
        decidedCouponsProvider
            .overrideWith((ref, limit) async => fixtureDecided),
        withdrawnCouponsProvider.overrideWith((ref) async => fixtureWithdrawn),
        featureFlagsProvider.overrideWith((ref) async => const {}),
        myPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const CouponsScreen(),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}

void main() {
  group('répartition en onglets', () {
    test('à jouer, en cours, décidé, retiré', () {
      expect(phaseOf(_byId('a'), _now), CouponPhase.toPlay);
      expect(phaseOf(_byId('l'), _now), CouponPhase.live);
      // Perdu alors qu'un match reste à jouer : décidé, donc dans Résultats.
      expect(phaseOf(_byId('d1'), _now), CouponPhase.decided);
      expect(phaseOf(_byId('x'), _now), CouponPhase.withdrawn);
    });

    test('à jouer trié par coup d’envoi, puis par cote', () {
      final s = splitActive(fixtureActive, _now);
      expect(_ids(s.toPlay), ['b', 'a']);
      expect(_ids(s.live), ['l']);
      expect(
          _ids(splitActive(fixtureActive, _now, sort: ToPlaySort.oddDesc)
              .toPlay),
          ['a', 'b']);
      expect(_ids(splitActive(fixtureActive, _now, category: 'du_jour').toPlay),
          ['a']);
    });

    test('sélections : état, score, progression, détail du résultat', () {
      final l = _byId('l');
      expect(selectionState(l.selections[0]), SelectionState.won);
      expect(selectionState(l.selections[1]), SelectionState.pending);
      expect(progressOf(l), (won: 1, total: 2));
      expect(resultDetail(_byId('d1')), 'Raté : Alpha 0–2 Beta');
      expect(resultDetail(_byId('w')), 'Toutes les sélections validées');
    });

    test(
        'résultats : par jour, période, type de résultat ; anciens accessibles',
        () {
      final days = groupByDay(fixtureDecided);
      expect(days.length, 3);
      expect(_ids(days.first.coupons), ['d1']);
      expect(days.first.lost, 1);
      expect(_ids(filterDecided(fixtureDecided, _now, days: 7)), ['d1', 'w']);
      expect(_ids(filterDecided(fixtureDecided, _now)), ['d1', 'w', 'old']);
      expect(resultPeriods.keys, isNot(contains(null)));
      expect(
          _ids(filterDecided(fixtureDecided, _now)
              .where(ResultKind.lost.accepts)),
          ['d1', 'old']);
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
    final t = couponShareText(_byId('a'));
    expect(t, contains('Alpha – Beta'));
    expect(t, contains('Cote totale 2,53'));
    expect(t, contains('aucune certitude'));
    for (final w in ['sûr', 'garanti', 'assuré']) {
      expect(t.toLowerCase(), isNot(contains(w)));
    }
  });

  testWidgets('À jouer par défaut, Coupon du jour en avant', (tester) async {
    await _pump(tester, _screen(const {}));
    expect(find.text('À jouer · 2'), findsOneWidget);
    expect(find.text('En cours · 1'), findsOneWidget);
    expect(find.text('Résultats · 2'), findsOneWidget);
    expect(find.text('COUPON DU JOUR'), findsOneWidget);
    expect(find.text('Coupon prudent'), findsNothing);
    expect(find.text('Prudent'), findsWidgets);
  });

  testWidgets('En cours : progression et état des sélections', (tester) async {
    await _pump(tester, _screen(const {}));
    await tester.tap(find.text('En cours · 1'));
    await tester.pumpAndSettle();
    expect(
        find.text('1 sélection validée sur 2 · encore en jeu'), findsOneWidget);
    expect(find.text('Alpha 2–0 Beta'), findsOneWidget);
    expect(find.textContaining('PROCHAIN MATCH'), findsOneWidget);
  });

  testWidgets('Résultats : bilan du jour, match décisif, anciens avec « Tout »',
      (tester) async {
    await _pump(tester, _screen(const {}));
    await tester.tap(find.text('Résultats · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Raté : Alpha 0–2 Beta'), findsOneWidget);
    expect(find.textContaining('pertes comprises'), findsWidgets);
    expect(find.text('Coupons retirés (1)'), findsOneWidget);
    expect(find.textContaining('Raté : Alpha 1–1 Beta'), findsNothing);

    await tester.tap(find.text('7 jours'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tout').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Raté : Alpha 1–1 Beta'), findsOneWidget);
    expect(find.text('Résultats · 3'), findsOneWidget);

    await tester.tap(find.text('Perdus'));
    await tester.pumpAndSettle();
    expect(find.text('Toutes les sélections validées'), findsNothing);
  });

  testWidgets('retirés : repliés, suppression réservée à l’équipe',
      (tester) async {
    await _pump(tester, _screen(const {}));
    await tester.tap(find.text('Résultats · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coupons retirés (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer définitivement'), findsNothing);

    // Nouvel arbre : les permissions d'un autre compte (équipe).
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _screen(const {'coupons.publish'}));
    await tester.tap(find.text('Résultats · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coupons retirés (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer définitivement'), findsOneWidget);
  });

  testWidgets('appui long : actions', (tester) async {
    await _pump(tester, _screen(const {}));
    await tester.longPress(find.text('COUPON DU JOUR'));
    await tester.pumpAndSettle();
    expect(find.text('Partager en texte'), findsOneWidget);
    expect(find.text('Supprimer définitivement'), findsNothing);
  });

  testWidgets('texte ×1,6 sans débordement, sur les trois onglets',
      (tester) async {
    await _pump(tester, _screen(const {'coupons.publish'}, scale: 1.6));
    expect(tester.takeException(), isNull);
    for (final t in ['En cours · 1', 'Résultats · 2']) {
      await tester.tap(find.text(t));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
