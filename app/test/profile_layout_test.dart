// Profil réorganisé (09/11) : ordre des sections, réglages regroupés, panneaux.
import 'package:coupon_pro_ia/core/monitoring/error_reporter.dart';
import 'package:coupon_pro_ia/core/providers.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_models.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_repository.dart';
import 'package:coupon_pro_ia/features/billing/billing_repository.dart';
import 'package:coupon_pro_ia/features/onboarding/data/preferences_repository.dart';
import 'package:coupon_pro_ia/features/profile/data/profile_repository.dart';
import 'package:coupon_pro_ia/features/profile/presentation/profile_screen.dart';
import 'package:coupon_pro_ia/features/system/app_updater.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUpdater implements NativeUpdater {
  @override
  Future<Map<String, dynamic>> status() async => {'state': 'none'};
  @override
  Future<void> startDownload(Map<String, Object?> args) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> canInstall() async => true;
  @override
  Future<void> openInstallSettings() async {}
  @override
  Future<bool> isUnmetered() async => true;
  @override
  Future<String> install() async => 'installing';
}

Future<void> _pump(WidgetTester t, {Set<String> perms = const {}}) async {
  SharedPreferences.setMockInitialValues({'app.language': 'fr'});
  final prefs = await SharedPreferences.getInstance();
  t.view.physicalSize = const Size(412, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final credits = Credits.fromJson(
      {'plan': 'FREE', 'total': 2, 'plan_credits': 2, 'extra_credits': 0});
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      errorReporterProvider.overrideWithValue(ErrorReporter(prefs)),
      currentUserProvider.overrideWith((ref) => null),
      myProfileProvider.overrideWith((ref) async => Profile(
          id: 'u',
          displayName: 'Toussaint',
          countryCode: 'BF',
          createdAt: DateTime(2026))),
      myPermissionsProvider.overrideWith((ref) async => perms),
      entitlementsProvider.overrideWith(
          (ref) async => Entitlements(plan: 'FREE', credits: credits)),
      myCreditsProvider.overrideWith((ref) async => credits),
      myPreferencesProvider.overrideWith(
          (ref) async => UserPreferences(onboardedAt: DateTime(2026))),
      installedPackageProvider.overrideWith((ref) async => PackageInfo(
          appName: 'a',
          packageName: 'p',
          version: '0.36.0',
          buildNumber: '2145')),
      nativeUpdaterProvider.overrideWithValue(_FakeUpdater()),
      latestAndroidVersionProvider.overrideWith((ref) async => null),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await t.pumpAndSettle();
}

double _y(WidgetTester t, String text) =>
    t.getTopLeft(find.text(text).first).dy;

void main() {
  testWidgets('ordre des sections et réglages regroupés', (t) async {
    await _pump(t);
    final order = [
      'Mon abonnement',
      'Mon jeu',
      'Communauté',
      'Réglages de l’application',
      'Aide',
      'Supprimer mon compte',
      'Se déconnecter',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(_y(t, order[i]), greaterThan(_y(t, order[i - 1])),
          reason: '${order[i - 1]} avant ${order[i]}');
    }
    // Tous les réglages de l'application sont dans leur section, sous son titre.
    for (final r in [
      'Notifications',
      'Langue',
      'Apparence',
      'Mises à jour',
      'Widget sur l’écran d’accueil',
      'Rapports d’erreurs'
    ]) {
      expect(_y(t, r), greaterThan(_y(t, 'Réglages de l’application')),
          reason: r);
      expect(_y(t, r), lessThan(_y(t, 'Aide')), reason: r);
    }
    expect(find.text('Compétitions et niveau'), findsOneWidget);
    expect(find.text('Mes préférences'), findsNothing);
    expect(find.text('Administration'), findsNothing,
        reason: 'réservé à l’équipe');
    // Crédits IA : ligne cliquable (flèche).
    final credits = find.ancestor(
        of: find.text('Crédits IA'), matching: find.byType(ListTile));
    expect(t.widget<ListTile>(credits).onTap, isNotNull);
    expect(find.text('Système · texte normal'), findsOneWidget);
  });

  testWidgets('équipe : section Administration ; panneau Apparence', (t) async {
    await _pump(t, perms: {'admin.access'});
    expect(find.text('Administration'), findsOneWidget);
    expect(_y(t, 'Administration'),
        greaterThan(_y(t, 'Réglages de l’application')));
    await t.tap(find.text('Apparence'));
    await t.pumpAndSettle();
    expect(find.text('Thème'), findsOneWidget);
    expect(find.text('Taille du texte'), findsOneWidget);
  });
}
