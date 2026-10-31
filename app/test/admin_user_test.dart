import 'package:coupon_pro_ia/features/admin/data/admin_repository.dart';
import 'package:coupon_pro_ia/features/admin/presentation/users_admin_screen.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _id = '780bf455-0d35-45cb-9aae-62d0805966a4';

Widget _screen(Set<String> perms, {double scale = 1}) => ProviderScope(
      overrides: [
        // Aucun appel réseau dans ces tests : client factice.
        adminRepositoryProvider.overrideWithValue(AdminRepository(
            SupabaseClient(
                'http://localhost:1', 'test',
                authOptions:
                    const AuthClientOptions(autoRefreshToken: false)))),
        myPermissionsProvider.overrideWith((ref) async => perms),
        publicSettingsProvider.overrideWith((ref) async => {
              'pricing.plans': [
                {'code': 'FREE'},
                {'code': 'STARTER'},
                {'code': 'PRO_TIPSTER'},
              ],
              'pricing.credit_pack': {'credits': 10, 'price_xof': 500},
            }),
        adminUserProvider.overrideWith((ref, id) async => {
              'id': _id,
              'email': 'bob@test.local',
              'display_name': 'Bob',
              'plan': 'FREE',
              'roles': ['user'],
              'credits': {'total': 2, 'unlimited': false},
              'activity': <String, dynamic>{},
              'created_at': '2026-10-31T13:00:00Z',
            }),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(400, 1600),
              textScaler: TextScaler.linear(scale)),
          child: const UserAdminDetailScreen(userId: _id),
        ),
      ),
    );

void main() {
  testWidgets('fiche : forfait et pack offerts visibles avec billing.manage',
      (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
        _screen({'admin.access', 'users.manage', 'billing.manage'}));
    await tester.pumpAndSettle();
    expect(find.text('Attribuer un forfait'), findsOneWidget);
    expect(find.text('Offrir un pack de crédits'), findsOneWidget);
    expect(find.textContaining('Pack : 10 crédits'), findsOneWidget);

    await tester.tap(find.text('Offrir un pack de crédits'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('20 crédits'), findsOneWidget);
  });

  testWidgets('fiche sans billing.manage : pas d’offre', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_screen({'admin.access', 'users.manage'}));
    await tester.pumpAndSettle();
    expect(find.text('Offrir un pack de crédits'), findsNothing);
  });

  testWidgets('fiche : texte ×1,6 sans débordement', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_screen(
        {'admin.access', 'users.manage', 'billing.manage'},
        scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
