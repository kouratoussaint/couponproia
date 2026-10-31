import 'package:coupon_pro_ia/core/providers.dart';
import 'package:coupon_pro_ia/features/analysis/presentation/analyze_access.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_models.dart';
import 'package:coupon_pro_ia/features/assistant/data/assistant_repository.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/profile/data/profile_repository.dart';
import 'package:coupon_pro_ia/features/profile/presentation/edit_profile_screen.dart';
import 'package:coupon_pro_ia/features/onboarding/data/preferences_repository.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/match_fixtures.dart';

Credits _credits(String plan, int total, {bool unlimited = false}) =>
    Credits.fromJson({
      'plan': plan,
      'total': total,
      'plan_credits': total,
      'extra_credits': 0,
      'unlimited': unlimited,
    });

Widget _button(Credits credits, {int? featured}) => ProviderScope(
      overrides: [
        myCreditsProvider.overrideWith((ref) async => credits),
        myPermissionsProvider.overrideWith((ref) async => <String>{}),
        featuredMatchProvider.overrideWith((ref) async => featured),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Center(child: AnalyzeMatchButton(match: lilleLens())))),
    );

void main() {
  test('analyse : forfait payant, crédits ou compte équipe', () {
    expect(canAnalyzeWith(_credits('STARTER', 0)), isTrue);
    expect(canAnalyzeWith(_credits('FREE', 2)), isTrue);
    expect(canAnalyzeWith(_credits('FREE', 0, unlimited: true)), isTrue);
    expect(canAnalyzeWith(_credits('FREE', 0)), isFalse);
    expect(canAnalyzeWith(null), isFalse);
  });

  testWidgets('bouton Analyser : actif avec des crédits', (tester) async {
    await tester.pumpWidget(_button(_credits('FREE', 2)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('bouton Analyser : verrouillé sans forfait ni crédit',
      (tester) async {
    await tester.pumpWidget(_button(_credits('FREE', 0)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.tap(find.text('Analyser'));
    await tester.pumpAndSettle();
    expect(find.text('Analyse réservée'), findsOneWidget);
  });

  testWidgets('bouton Analyser : analyse offerte du jour ouverte à tous',
      (tester) async {
    await tester
        .pumpWidget(_button(_credits('FREE', 0), featured: lilleLens().id));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('profil : toutes les informations modifiables', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myProfileProvider.overrideWith((ref) async => Profile(
            id: 'u',
            displayName: 'Toussaint',
            countryCode: 'BF',
            createdAt: DateTime(2026),
            timezone: 'Africa/Ouagadougou')),
        currentUserProvider.overrideWith((ref) => null),
        myPreferencesProvider.overrideWith((ref) async => UserPreferences(
            onboardedAt: DateTime(2026), level: UserLevel.intermediaire)),
      ],
      child: const MaterialApp(home: EditProfileScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Toussaint'), findsOneWidget);
    expect(find.text('Burkina Faso'), findsOneWidget);
    expect(find.text('Changer le mot de passe'), findsOneWidget);
    expect(find.text('Adresse e-mail'), findsOneWidget);
    expect(find.text('Compétitions suivies'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
