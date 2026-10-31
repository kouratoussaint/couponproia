import 'package:coupon_pro_ia/core/providers.dart';
import 'package:coupon_pro_ia/core/router/app_router.dart';
import 'package:coupon_pro_ia/features/legal/legal_repository.dart';
import 'package:coupon_pro_ia/features/legal/legal_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'documents : champs de l’éditeur remplis, champs vides retirés proprement',
      () {
    const body =
        'Édité par {{editeur}} {{forme}}, {{adresse}}, {{pays}}, {{immatriculation}}. Contact : {{contact}}.';
    expect(
        fillLegalPlaceholders(body, {
          'legal.editor': {
            'name': 'Kour SARL',
            'legal_form': '(SARL)',
            'address': 'Ouagadougou',
            'country': 'Burkina Faso',
            'registration': 'RCCM BF-OUA-01'
          },
          'app.support_email': 'support@exemple.com',
        }),
        'Édité par Kour SARL (SARL), Ouagadougou, Burkina Faso, RCCM BF-OUA-01. Contact : support@exemple.com.');
    expect(
        fillLegalPlaceholders(body, {
          'legal.editor': {'country': 'Burkina Faso'},
          'app.support_email': null,
        }),
        'Édité par l’éditeur de Coupon Pro IA, Burkina Faso. Contact : le support (Profil → Contacter le support).');
  });

  test('documents légaux lisibles connecté ou non', () {
    for (final signedIn in [true, false]) {
      expect(
          resolveRedirect(
              isConfigured: true,
              isSignedIn: signedIn,
              location: '/documents/terms'),
          isNull);
    }
  });

  testWidgets('mise en forme : titres, puces, gras', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: LegalText(
                '## 1. Objet\nTexte **important** ici.\n- point A\n- point B'))));
    expect(find.text('1. Objet'), findsOneWidget);
    expect(find.textContaining('point A', findRichText: true), findsOneWidget);
    expect(
        find.textContaining('important', findRichText: true), findsOneWidget);
  });

  testWidgets('acceptation : bouton actif seulement après la case cochée',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: LegalAcceptanceScreen(
          pending: const [
            PendingDocument(
                id: 1,
                code: 'terms',
                version: '2026-10-31',
                title: 'Conditions générales d’utilisation'),
            PendingDocument(
                id: 2,
                code: 'privacy',
                version: '2026-10-31',
                title: 'Politique de confidentialité'),
          ],
          onSignOut: () async {},
        ),
      ),
    ));
    expect(find.text('Version du 31/10/2026'), findsNWidgets(2));
    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });
}
