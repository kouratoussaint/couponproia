// LOT 25 : sélection des championnats (console).
import 'dart:convert';
import 'dart:io';

import 'package:coupon_pro_ia/core/i18n/tr.dart';
import 'package:coupon_pro_ia/features/admin/data/competitions_admin_repository.dart';
import 'package:coupon_pro_ia/features/admin/presentation/competitions_admin_screen.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _competitions = [
  AdminCompetition.fromJson({
    'id': 8,
    'name': 'Africa Cup of Nations',
    'display_name': 'Africa Cup of Nations',
    'status': 'active',
    'priority': 4,
    'quality_override': true,
    'quality': {'matches': 22, 'verdict': null},
  }),
  AdminCompetition.fromJson({
    'id': 5,
    'name': 'Ligue 1',
    'display_name': 'Ligue 1 (France)',
    'country': 'France',
    'status': 'active',
    'priority': 50,
    'open_coupons': 3,
    'matches_14d': 18,
    'quality': {
      'matches': 326,
      'brier_model': 0.603,
      'brier_baseline': 0.657,
      'verdict': true
    },
  }),
  AdminCompetition.fromJson({
    'id': 21,
    'name': 'Ligue 1',
    'display_name': 'Ligue 1 (Burkina-Faso)',
    'country': 'Burkina-Faso',
    'status': 'observation',
    'priority': 130,
  }),
];

Widget _app({Set<String> permissions = const {'sports.configure'}}) =>
    ProviderScope(
      overrides: [
        adminCompetitionsProvider.overrideWith((ref) async => _competitions),
        catalogSearchProvider
            .overrideWith((ref, q) async => const CatalogSearch(
                  size: 1200,
                  results: [
                    CatalogLeague(
                        providerRef: '386',
                        name: 'Ligue 1',
                        country: 'Ivory-Coast',
                        odds: true),
                    CatalogLeague(
                        providerRef: '61',
                        name: 'Ligue 1',
                        country: 'France',
                        status: CompetitionStatus.active),
                  ],
                )),
        myPermissionsProvider.overrideWith((ref) async => permissions),
      ],
      child: const MaterialApp(home: CompetitionsAdminScreen()),
    );

void main() {
  tearDown(() => setLanguageForTest('fr', const {}));

  test('modèles : état, verdict et coupons automatiques', () {
    expect(_competitions[0].inAutomaticCoupons, isTrue, reason: 'CAN forcée');
    expect(_competitions[1].inAutomaticCoupons, isTrue);
    expect(_competitions[2].inAutomaticCoupons, isFalse, reason: 'observation');
    expect(qualityLine(_competitions[1]),
        'Moteur : verdict positif sur 326 matchs (Brier 0,603 contre 0,657)');
    expect(qualityLine(_competitions[0]),
        contains('admise par le super administrateur'));
    expect(
        CompetitionRef.fromJson({
          'id': 21,
          'name': 'Ligue 1',
          'display_name': 'Ligue 1 (Burkina-Faso)'
        }).name,
        'Ligue 1 (Burkina-Faso)');
  });

  testWidgets('liste, filtres et fiche d’une compétition', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Ligue 1 (Burkina-Faso)'), findsOneWidget);
    expect(find.text('En observation'), findsOneWidget);
    await tester.ensureVisible(find.text('En observation (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('En observation (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Ligue 1 (France)'), findsNothing);
    await tester.ensureVisible(find.text('Toutes (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toutes (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ligue 1 (France)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inactif').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 coupon(s) non réglé(s)'), findsOneWidget);
    // Forçage réservé au super administrateur.
    expect(find.text('Admettre sans verdict du moteur'), findsNothing);
  });

  testWidgets('forçage visible pour le super administrateur', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        _app(permissions: {'sports.configure', 'competitions.override'}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Africa Cup of Nations'));
    await tester.pumpAndSettle();
    expect(find.text('Admettre sans verdict du moteur'), findsOneWidget);
  });

  testWidgets('catalogue : ajouter ou état déjà suivi', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        catalogSearchProvider
            .overrideWith((ref, q) async => const CatalogSearch(
                  size: 1200,
                  results: [
                    CatalogLeague(
                        providerRef: '386',
                        name: 'Ligue 1',
                        country: 'Ivory-Coast'),
                    CatalogLeague(
                        providerRef: '61',
                        name: 'Ligue 1',
                        country: 'France',
                        status: CompetitionStatus.active),
                  ],
                )),
      ],
      child:
          const MaterialApp(home: CatalogSearchScreen(initialQuery: 'Ligue 1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter'), findsOneWidget);
    expect(find.text('Actif'), findsOneWidget);
  });

  testWidgets('écran en anglais', (tester) async {
    setLanguageForTest(
        'en',
        Map<String, String>.from(
            jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map));
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Competitions'), findsOneWidget);
    expect(find.text('Under observation'), findsOneWidget);
    expect(find.text('3 competitions tracked'), findsOneWidget);
  });
}
