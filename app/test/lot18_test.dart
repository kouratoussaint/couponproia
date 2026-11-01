// Lot 18 : liens de partage, renouvellement, conversion et rétention, notifications ciblées.
import 'package:coupon_pro_ia/core/share_links.dart';
import 'package:coupon_pro_ia/features/admin/presentation/campaigns_admin_screen.dart';
import 'package:coupon_pro_ia/features/admin/presentation/growth_admin_screen.dart';
import 'package:coupon_pro_ia/features/billing/billing_repository.dart';
import 'package:coupon_pro_ia/features/billing/renewal_banner.dart';
import 'package:coupon_pro_ia/features/coupons/presentation/coupon_actions.dart';
import 'package:coupon_pro_ia/features/notifications/data/notifications_repository.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coupon_fixtures.dart';

void main() {
  group('liens de partage', () {
    test('adresse publique du coupon et du match', () {
      expect(shareLinkFor('https://p.supabase.co/', couponId: 'abc'),
          'https://p.supabase.co/functions/v1/share/c/abc');
      expect(shareLinkFor('https://p.supabase.co', matchId: 5988),
          'https://p.supabase.co/functions/v1/share/m/5988');
    });

    test('le texte partagé contient le lien', () {
      final c = fixtureCoupon('x');
      final text = couponShareText(c, link: 'https://l/c/x');
      expect(text, contains('Ouvrir dans l’app : https://l/c/x'));
      expect(couponShareText(c), isNot(contains('Ouvrir dans')));
    });
  });

  group('renouvellement', () {
    test('forfait et durée repris dans le lien', () {
      final r = Renewal.fromJson({
        'plan_code': 'PRO_TIPSTER',
        'period': 'annual',
        'period_end': '2026-11-03T10:00:00Z',
        'ended': false,
      })!;
      expect(r.route, '/abonnement?renouveler=PRO_TIPSTER&periode=annual');
      expect(Renewal.fromJson(null), isNull);
    });

    testWidgets('bandeau d’accueil', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          renewalProvider.overrideWith((ref) async => Renewal(
              planCode: 'STARTER',
              annual: false,
              periodEnd: DateTime(2026, 11, 3, 9),
              ended: false)),
        ],
        child: const MaterialApp(home: Scaffold(body: RenewalBanner())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Votre forfait STARTER se termine le 03/11'),
          findsOneWidget);
      expect(find.text('Renouveler'), findsOneWidget);
    });
  });

  group('notifications ciblées', () {
    test('mêmes mots interdits que le serveur', () {
      expect(hasForbiddenWords('Gain assuré ce soir'), isTrue);
      expect(hasForbiddenWords('Pronostic 100 % sûr'), isTrue);
      expect(hasForbiddenWords('Nouveautés : le simulateur de mise'), isFalse);
      expect(hasForbiddenWords('Une gaine'), isFalse);
    });

    testWidgets('envoi bloqué tant que le message n’est pas conforme',
        (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          myPermissionsProvider.overrideWith((ref) async => {'campaigns.send'}),
          campaignAudienceProvider
              .overrideWith((ref, s) async => s == 'all' ? 42 : 3),
          campaignsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: CampaignsAdminScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Audience : 42 utilisateurs'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Titre'), 'Gain assuré');
      await tester.enterText(
          find.widgetWithText(TextField, 'Message'), 'Venez voir');
      await tester.pumpAndSettle();
      expect(find.textContaining('Mot interdit'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.ancestor(
          of: find.text('Envoyer'),
          matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(button.onPressed, isNull);
      await tester.enterText(
          find.widgetWithText(TextField, 'Titre'), 'Nouveautés');
      await tester.pumpAndSettle();
      final ok = tester.widget<FilledButton>(find.ancestor(
          of: find.text('Envoyer'),
          matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(ok.onPressed, isNotNull);
      await tester.tap(find.text('Forfait qui se termine'));
      await tester.pumpAndSettle();
      expect(find.text('Audience : 3 utilisateurs'), findsOneWidget);
    });

    test('préférence « Annonces et offres »', () {
      final p = NotificationPrefs.fromJson({'notify_news': false});
      expect(prefValue(p, 'notify_news'), isFalse);
    });
  });

  group('conversion et rétention', () {
    testWidgets('entonnoir et cohortes', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          myPermissionsProvider.overrideWith((ref) async => {'growth.read'}),
          growthProvider.overrideWith((ref, d) async => {
                'days': d,
                'funnel': {
                  'signed_up': 40,
                  'onboarded': 30,
                  'came_back': 20,
                  'first_purchase': 8,
                  'renewed': 2
                },
                'period': {
                  'new_paying': 8,
                  'renewals': 3,
                  'revenue_xof': 26000,
                  'paying_now': 10,
                  'users_total': 100,
                  'share_opens': 12,
                  'share_opens_android': 11
                },
                'active': {'day': 15, 'week': 50, 'month': 80},
                'cohorts': [
                  {
                    'week': '2026-10-26',
                    'users': 20,
                    'd7_eligible': 0,
                    'd7': 0,
                    'd30_eligible': 0,
                    'd30': 0,
                    'paid': 4
                  },
                  {
                    'week': '2026-10-19',
                    'users': 10,
                    'd7_eligible': 10,
                    'd7': 6,
                    'd30_eligible': 0,
                    'd30': 0,
                    'paid': 2
                  },
                ],
              }),
        ],
        child: const MaterialApp(home: GrowthAdminScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('8 · 20 %'), findsOneWidget);
      expect(find.text('60 %'), findsOneWidget);
      expect(find.textContaining('12 (dont 11 sur Android)'), findsOneWidget);
      expect(share(1, 0), '—');
    });
  });
}
