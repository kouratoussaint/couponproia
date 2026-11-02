// Version 0.28.0 : menu latéral réorganisé et Mes coupons (C1 à C8).
import 'package:coupon_pro_ia/features/assistant/data/assistant_models.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_repository.dart';
import 'package:coupon_pro_ia/features/assistant/data/my_coupons_view.dart';
import 'package:coupon_pro_ia/features/assistant/presentation/my_coupons_screen.dart';
import 'package:coupon_pro_ia/features/profile/data/profile_repository.dart';
import 'package:coupon_pro_ia/features/shell/app_drawer.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _now = DateTime.now();

Map<String, dynamic> _sel(int pos, String home, String away) => {
      'position': pos,
      'selection_key': 'HOME',
      'odd': 1.5,
      'odds_captured_at': _now.toUtc().toIso8601String(),
      'model_probability': 0.6,
      'match': {
        'id': pos,
        'kickoff_at': _now.toUtc().toIso8601String(),
        'status': 'finished',
        'home': {'name': home},
        'away': {'name': away},
        'competition': {'name': 'Liga'},
      },
    };

UserCoupon _coupon(String id,
        {String title = 'Mon coupon · 4 sélections · cote 5,19',
        String? result,
        int n = 4,
        double odd = 5.19,
        String? conversation,
        Map<String, dynamic> analysis = const {'manual': true},
        Duration settledAgo = const Duration(hours: 1)}) =>
    UserCoupon.fromJson({
      'id': id,
      'status': 'saved',
      'title': title,
      'total_odd': odd,
      'combined_probability': 0.29,
      'risk_level': 'equilibre',
      'engine_version': 'v',
      'conversation_id': conversation,
      'created_at': DateTime(2026, 11, 1, 14, 32).toUtc().toIso8601String(),
      'analysis': analysis,
      'result': result,
      'settled_odd': result == 'won' ? odd : null,
      'settled_at': result == null
          ? null
          : _now.subtract(settledAgo).toUtc().toIso8601String(),
      'user_coupon_selections': [
        for (var i = 1; i <= n; i++) _sel(i, 'Équipe A$i', 'Équipe B$i')
      ],
    });

Credits _credits(String plan, int total, {bool unlimited = false}) =>
    Credits.fromJson({
      'plan': plan,
      'total': total,
      'plan_credits': total,
      'extra_credits': 0,
      'unlimited': unlimited,
    });

void main() {
  test('titre selon l’origine, nom choisi conservé', () {
    expect(displayTitle(_coupon('a')), 'Coupon manuel · 4 sélections');
    expect(
        displayTitle(_coupon('b',
            title: 'Coupon 3 sélections · cote 4,10',
            n: 3,
            conversation: 'conv',
            analysis: const {})),
        'Coupon de l’assistant · 3 sélections');
    expect(
        displayTitle(_coupon('c',
            n: 1, analysis: const {'manual': true, 'variant_of': 'x'})),
        'Version optimisée · 1 sélection');
    expect(displayTitle(_coupon('d', title: 'Mon combiné du samedi')),
        'Mon combiné du samedi');
  });

  test('deux matchs au plus, dates complètes', () {
    final c = _coupon('a');
    expect(matchesLine(c),
        'Équipe A1 – Équipe B1 · Équipe A2 – Équipe B2 · +2 matchs');
    expect(myCouponDateLine(c), 'Créé le 01/11/2026 à 14:32');
    expect(
        myCouponDateLine(_coupon('w', result: 'won')), contains('· Payé le '));
    expect(myCouponDateLine(_coupon('l', result: 'lost')),
        contains('· Terminé le '));
  });

  test('bilan : réussite hors annulés, cote moyenne des décidés', () {
    final s = summarize([
      _coupon('1', result: 'won', odd: 2),
      _coupon('2', result: 'lost', odd: 4),
      _coupon('3', result: 'void'),
      _coupon('4'),
    ]);
    expect(s.total, 4);
    expect(s.inProgress, 1);
    expect(s.successRate, 0.5);
    expect(s.averageOdd, 3);
    expect(summarize(const []).successRate, isNull);
  });

  test('terminés groupés par jour de règlement, du plus récent', () {
    final groups = decidedByDay([
      _coupon('old', result: 'lost', settledAgo: const Duration(days: 2)),
      _coupon('new', result: 'won', settledAgo: const Duration(minutes: 5)),
      _coupon('pending'),
    ]);
    expect(groups, hasLength(2));
    expect(groups.first.$2.single.id, 'new');
  });

  Future<void> pumpList(WidgetTester tester, List<UserCoupon> list,
      {double scale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        savedCouponsProvider.overrideWith((ref) async => list),
        myCreditsProvider.overrideWith((ref) async => _credits('FREE', 3)),
        publicSettingsProvider.overrideWith((ref) async => <String, dynamic>{}),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const MyCouponsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Mes coupons : la date reste visible avec 4 matchs',
      (tester) async {
    await pumpList(tester, [_coupon('a', result: 'won'), _coupon('b')]);
    expect(find.text('Mon bilan'), findsOneWidget);
    expect(find.text('En cours'), findsWidgets);
    expect(find.textContaining('+2 matchs'), findsNWidgets(2));
    expect(find.textContaining('Créé le 01/11/2026 à 14:32'), findsNWidgets(2));
    expect(find.textContaining('Payé le '), findsOneWidget);
    expect(find.text('Créer un coupon'), findsOneWidget);
  });

  testWidgets('Mes coupons : texte ×1,6 sans débordement', (tester) async {
    await pumpList(
        tester, [_coupon('a', result: 'lost'), _coupon('b', result: 'won')],
        scale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mes coupons : actions, sans renommer un coupon publié',
      (tester) async {
    await pumpList(tester, [_coupon('a')]);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    for (final t in [
      'Ouvrir dans le laboratoire',
      'Simuler une mise',
      'Noter dans mon carnet',
      'Partager (copier le coupon)',
      'Renommer',
      'Supprimer',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('1 crédit par calcul'), findsOneWidget);
  });

  testWidgets('Mes coupons vide : bouton Créer un coupon', (tester) async {
    await pumpList(tester, const []);
    await tester.tap(find.text('Créer un coupon'));
    await tester.pumpAndSettle();
    expect(find.text('Avec l’assistant'), findsOneWidget);
    expect(find.text('Dans le laboratoire'), findsOneWidget);
  });

  Future<void> pumpDrawer(WidgetTester tester, Credits credits,
      {Set<String> permissions = const {}}) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myCreditsProvider.overrideWith((ref) async => credits),
        myPermissionsProvider.overrideWith((ref) async => permissions),
        myProfileProvider.overrideWith((ref) async => Profile(
            id: 'u',
            displayName: 'Toussaint',
            countryCode: 'BF',
            createdAt: DateTime(2026))),
        installedPackageProvider.overrideWith((ref) async => PackageInfo(
            appName: 'a',
            packageName: 'p',
            version: '0.28.0',
            buildNumber: '135')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AppDrawer(currentIndex: 2, onSelectTab: (_) {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'menu : forfait réel, crédits, sections et Performances publiques',
      (tester) async {
    await pumpDrawer(tester, _credits('PRO', 50));
    expect(find.text('Forfait PRO'), findsOneWidget);
    expect(find.text('50 crédits'), findsOneWidget);
    expect(find.text('Voir les forfaits'), findsNothing);
    for (final t in [
      'MON ESPACE ET COMPTE',
      'DÉCOUVRIR',
      'OUTILS',
      'AIDE',
      'Coupons IA',
      'Performances',
      'Jeu responsable',
      'Contacter le support',
      'Mentions légales et documents',
      'Se déconnecter',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('ADMINISTRATION'), findsNothing);
    expect(find.text('Console d’administration'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('menu : FREE → Voir les forfaits', (tester) async {
    await pumpDrawer(tester, _credits('FREE', 0));
    expect(find.text('Voir les forfaits'), findsOneWidget);
    expect(find.text('Forfait FREE'), findsOneWidget);
  });

  testWidgets('menu : équipe → Administration', (tester) async {
    await pumpDrawer(tester, _credits('FREE', 0, unlimited: true),
        permissions: {'admin.access'});
    expect(find.text('Compte équipe'), findsOneWidget);
    expect(find.text('Illimités'), findsOneWidget);
    expect(find.text('ADMINISTRATION'), findsOneWidget);
    expect(find.text('Console d’administration'), findsOneWidget);
  });
}
