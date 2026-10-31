import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/matches/presentation/match_tabs.dart';
import 'package:coupon_pro_ia/features/onboarding/data/preferences_repository.dart';
import 'package:coupon_pro_ia/features/onboarding/presentation/onboarding_sheet.dart';
import 'package:coupon_pro_ia/features/profile/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePrefs implements PreferencesRepository {
  Set<int>? favorites;
  UserLevel? level;
  bool onboarded = false;

  @override
  Future<UserPreferences?> mine() async => const UserPreferences();

  @override
  Future<void> save(
      {Set<int>? favoriteCompetitions,
      UserLevel? level,
      bool markOnboarded = false}) async {
    favorites = favoriteCompetitions;
    this.level = level;
    onboarded = markOnboarded;
  }
}

class _FakeProfiles implements ProfileRepository {
  String? saved;

  @override
  Future<void> updateDisplayName(String name) async => saved = name.trim();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('préférences lues depuis la base', () {
    final p = UserPreferences.fromJson({
      'favorite_competitions': [39, 61],
      'level': 'expert',
      'onboarded_at': '2026-10-31T06:00:00Z',
    });
    expect(p.favoriteCompetitions, {39, 61});
    expect(p.level, UserLevel.expert);
    expect(p.needsOnboarding, isFalse);
    expect(p.showExplanations, isFalse);
    expect(
        UserPreferences.fromJson({'favorite_competitions': null})
            .needsOnboarding,
        isTrue);
    expect(const UserPreferences().showExplanations, isTrue);
  });

  testWidgets('parcours en 3 étapes : pseudo, compétitions, niveau',
      (tester) async {
    final prefs = _FakePrefs();
    final profiles = _FakeProfiles();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(prefs),
        profileRepositoryProvider.overrideWithValue(profiles),
        myPreferencesProvider
            .overrideWith((ref) async => const UserPreferences()),
        myProfileProvider.overrideWith((ref) async => null),
        competitionsProvider.overrideWith((ref) async => const [
              CompetitionRef(id: 39, name: 'Premier League', priority: 1),
              CompetitionRef(id: 61, name: 'Ligue 1', priority: 2),
            ]),
      ],
      child: const MaterialApp(home: Scaffold(body: OnboardingSheet())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Au moins 2 caractères.'), findsOneWidget,
        reason: 'pseudo obligatoire pour continuer');

    await tester.enterText(find.byType(TextField), '  Kouassi ');
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Étape 2 sur 3'), findsOneWidget);
    await tester.tap(find.text('Ligue 1'));
    await tester.pump();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.text('Étape 3 sur 3'), findsOneWidget);
    await tester.tap(find.text('Débutant'));
    await tester.pump();
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();

    expect(profiles.saved, 'Kouassi');
    expect(prefs.favorites, {61});
    expect(prefs.level, UserLevel.debutant);
    expect(prefs.onboarded, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '« Plus tard » : le parcours ne revient plus, rien d’autre n’est modifié',
      (tester) async {
    final prefs = _FakePrefs();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(prefs),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
        myPreferencesProvider
            .overrideWith((ref) async => const UserPreferences()),
        myProfileProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: OnboardingSheet())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(prefs.onboarded, isTrue);
    expect(prefs.favorites, isNull);
    expect(prefs.level, isNull);
  });

  testWidgets('définitions des termes pour un débutant', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: GlossaryCard())));
    await tester.tap(find.text('Comprendre ces chiffres'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 ÷ probabilité'), findsOneWidget);
    expect(find.textContaining('pas une certitude'), findsOneWidget);
  });
}
