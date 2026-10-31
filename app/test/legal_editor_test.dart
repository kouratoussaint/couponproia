import 'package:coupon_pro_ia/features/admin/data/admin_repository.dart';
import 'package:coupon_pro_ia/features/admin/presentation/legal_admin_screen.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Widget _card(Map<String, dynamic> settings) => ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(AdminRepository(
            SupabaseClient(
                'http://localhost:1', 'test',
                authOptions:
                    const AuthClientOptions(autoRefreshToken: false)))),
        publicSettingsProvider.overrideWith((ref) async => settings),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(child: EditorIdentityCard()))),
    );

void main() {
  testWidgets('identité vide : champs à compléter signalés', (tester) async {
    await tester.pumpWidget(_card({
      'legal.editor': {'name': '', 'country': 'Burkina Faso'},
      'app.support_email': null,
    }));
    await tester.pumpAndSettle();
    expect(find.text('Pays : Burkina Faso'), findsOneWidget);
    expect(find.textContaining('À compléter : nom, adresse, e-mail du support'),
        findsOneWidget);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Nom ou raison sociale'), findsOneWidget);
    expect(find.text('E-mail du support'), findsWidgets);
  });

  testWidgets('identité complète : rien à signaler', (tester) async {
    await tester.pumpWidget(_card({
      'legal.editor': {
        'name': 'Coupon Pro IA',
        'address': 'Ouagadougou',
        'country': 'Burkina Faso'
      },
      'app.support_email': 'contact@exemple.com',
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('À compléter'), findsNothing);
    expect(
        find.text('E-mail du support : contact@exemple.com'), findsOneWidget);
  });
}
