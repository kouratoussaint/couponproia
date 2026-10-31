import 'package:coupon_pro_ia/features/admin/data/admin_repository.dart';
import 'package:coupon_pro_ia/features/admin/presentation/admin_console_screen.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _dashboard({int aiErrors = 0}) => {
      'days': 7,
      'users': {
        'total': 1240,
        'new': 85,
        'active': 410,
        'suspended': 2,
        'tipsters': 14
      },
      'coupons': {
        'generated': 42,
        'published': 35,
        'won': 12,
        'lost': 9,
        'withdrawn': 1,
        'pending_review': 3,
        'user_saved': 120,
        'tipster_published': 18
      },
      'ai': {
        'requests': 980,
        'match_analyses': 610,
        'errors': aiErrors,
        'cost_usd': 0.6123,
        'credits_consumed': 342
      },
      'billing': {
        'active_subscriptions': 37,
        'revenue_xof': 128500,
        'payments': {'succeeded': 41, 'pending': 3, 'failed': 2}
      },
      'community': {'posts': 54, 'comments': 210, 'open_reports': 4},
      'data': {
        'requests_used': 4100,
        'requests_today': 610,
        'requests_remaining': 6890,
        'failed_syncs': 0
      },
      'errors': {'ai': aiErrors, 'sync': 0, 'generation': 1, 'payments': 2},
      'daily': [
        for (var i = 0; i < 7; i++)
          {
            'day': '2026-10-2${i + 1}',
            'new_users': i * 3,
            'analyses': 80,
            'revenue_xof': 15000
          }
      ],
    };

void main() {
  test('lecture souple des données', () {
    expect(asInt(null), 0);
    expect(asInt(3.0), 3);
    expect(asList(null), isEmpty);
    expect(asMap('x'), isEmpty);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('tableau de bord (texte ×$scale)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DashboardView(data: _dashboard(aiErrors: 2)))),
        builder: (c, w) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!),
      ));
      await tester.pump();
      expect(find.text('1240'), findsOneWidget);
      expect(find.text('Erreurs système'), findsOneWidget);
      expect(find.text('5'), findsWidgets);
      expect(find.text('Nouveaux utilisateurs par jour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.6]) {
    testWidgets('console : familles colorées et compteurs (texte ×$scale)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          myPermissionsProvider.overrideWith((ref) async => {
                'admin.access',
                'users.manage',
                'generation.manage',
                'moderation.manage',
                'audit.read',
                'ai.providers',
                'ai.configure',
                'sports.configure',
                'billing.manage',
                'settings.manage',
                'flags.manage',
              }),
          adminDashboardProvider
              .overrideWith((ref, days) async => _dashboard()),
        ],
        child: MaterialApp(
          home: const AdminConsoleScreen(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Super admin'), findsOneWidget);
      expect(find.text('utilisateurs actifs'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('PILOTAGE'), 400,
          scrollable: list);
      await tester.scrollUntilVisible(find.text('Fournisseurs d’IA'), 300,
          scrollable: list);
      await tester.scrollUntilVisible(find.text('Documents légaux'), 300,
          scrollable: list);
      expect(tester.takeException(), isNull);
    });
  }
}
