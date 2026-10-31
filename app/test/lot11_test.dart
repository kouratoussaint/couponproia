import 'package:coupon_pro_ia/features/billing/billing_repository.dart';
import 'package:coupon_pro_ia/features/matches/data/matchday_models.dart';
import 'package:coupon_pro_ia/features/matches/presentation/match_tabs.dart';
import 'package:coupon_pro_ia/features/notifications/data/notifications_repository.dart';
import 'package:coupon_pro_ia/features/notifications/data/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/match_fixtures.dart';

void main() {
  test('notification lue depuis la base', () {
    final n = AppNotification.fromJson({
      'id': 4,
      'kind': 'result',
      'title': 'Coupon gagné',
      'body': '« Mon coupon » : gagné à la cote 2,10.',
      'route': '/mes-coupons/abc',
      'created_at': '2026-10-31T18:00:00Z',
      'read_at': null,
    });
    expect(n.isRead, isFalse);
    expect(n.route, '/mes-coupons/abc');
    expect(
        AppNotification.fromJson({
          ...{
            'id': 1,
            'kind': 'system',
            'title': 't',
            'body': 'b',
            'created_at': '2026-10-31T18:00:00Z'
          },
          'route': ''
        }).route,
        isNull);
  });

  test(
      'réglages par défaut : tout sauf le rendez-vous du matin, heures calmes 23 h → 7 h',
      () {
    final p = NotificationPrefs.fromJson(const {});
    expect(
        p.enabled &&
            p.coupons &&
            p.results &&
            p.tipsters &&
            p.matches &&
            p.credits,
        isTrue);
    expect(p.morning, isFalse);
    expect((p.quietStart, p.quietEnd), (23, 7));
    expect(
        NotificationPrefs.fromJson(const {'quiet_start': 0, 'quiet_end': 0})
            .hasQuietHours,
        isFalse);
  });

  test(
      'seules les pages internes de l’app peuvent être ouvertes par une notification',
      () {
    expect(routeOf({'route': '/coupon/123'}), '/coupon/123');
    expect(routeOf({'route': 'https://exemple.com'}), isNull);
    expect(routeOf({'route': '//exemple.com'}), isNull);
    expect(routeOf({'route': ''}), isNull);
    expect(routeOf(const {}), isNull);
  });

  test('sans configuration Firebase : aucune notification sur le téléphone',
      () {
    expect(FirebaseConfig.fromEnvironment.isConfigured, isFalse);
    const partial =
        FirebaseConfig(apiKey: 'k', appId: '', senderId: '1', projectId: 'p');
    expect(partial.isConfigured, isFalse);
  });

  test('absents : motifs traduits, incertains reconnus', () {
    expect(absenceReason('Knee Injury'), 'blessure au genou');
    expect(absenceReason('Red Card'), 'suspendu (carton rouge)');
    expect(absenceReason('Broken toe'), 'Broken toe');
    expect(absenceReason(null), 'motif non précisé');
    final a = Absence.fromJson(const {
      'team_id': 1,
      'player_name': 'X',
      'absence_type': 'Questionable',
      'reason': 'Knock',
      'fetched_at': '2026-10-31T10:00:00Z',
    });
    expect(a.uncertain, isTrue);
  });

  Widget wrap(Matchday d, {double scale = 1}) => ProviderScope(
        overrides: [matchdayProvider.overrideWith((ref, id) async => d)],
        child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: MatchdayCard(match: lilleLens()))),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
        ),
      );

  testWidgets('avant publication : heure attendue des compositions',
      (tester) async {
    await tester.pumpWidget(wrap(const Matchday(lineups: [], absences: [])));
    await tester.pumpAndSettle();
    expect(find.text('Compositions et absents'), findsOneWidget);
    expect(find.textContaining('Compositions officielles attendues vers'),
        findsOneWidget);
    expect(find.textContaining('Absents pas encore vérifiés'), findsOneWidget);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('compositions et absents publiés (texte ×$scale)',
        (tester) async {
      final m = lilleLens();
      final at = DateTime.parse('2026-10-30T19:30:00Z').toLocal();
      await tester.pumpWidget(wrap(
        Matchday(
          lineups: [
            TeamLineup(
              teamId: m.home.id,
              formation: '4-2-3-1',
              coach: 'B. Genesio',
              startXI: [
                for (var i = 1; i <= 11; i++)
                  LineupPlayer(
                      name: 'Joueur numéro $i avec un nom long', number: i)
              ],
              substitutes: const [],
              fetchedAt: at,
            ),
          ],
          absences: [
            Absence(
                teamId: m.away.id,
                player: 'F. Sotoca',
                type: 'Missing Fixture',
                reason: 'Hamstring Injury',
                fetchedAt: at),
            Absence(
                teamId: m.away.id,
                player: 'N. Saint-Maximin',
                type: 'Questionable',
                reason: 'Knock',
                fetchedAt: at),
          ],
        ),
        scale: scale,
      ));
      await tester.pumpAndSettle();
      expect(find.text('4-2-3-1 · entraîneur B. Genesio'), findsOneWidget);
      expect(find.text('F. Sotoca : blessure aux ischio-jambiers'),
          findsOneWidget);
      expect(find.text('Incertains'), findsOneWidget);
      expect(find.textContaining('API-Football · relevé à'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('code promo : portée et prix réduit identiques au serveur', () {
    final q = PromoQuote.fromJson({
      'ok': true,
      'code': 'BIENVENUE',
      'percent_off': 20,
      'applies_to': 'subscription',
      'plan_codes': ['STARTER'],
      'description': 'Offre de lancement',
      'ends_at': null,
    });
    expect(q.appliesToPlan('STARTER'), isTrue);
    expect(q.appliesToPlan('PRO_TIPSTER'), isFalse);
    expect(q.appliesToCredits, isFalse);
    expect(q.discounted(2000), 1600);
    expect(q.discounted(20400), 16320);
    const all = PromoQuote(code: 'X', percentOff: 33);
    expect(all.appliesToPlan('BUSINESS'), isTrue);
    expect(all.appliesToCredits, isTrue);
    expect(all.discounted(505), 340);
    expect(promoReasonMessage('already_used'), contains('déjà utilisé'));
    expect(promoReasonMessage('???'), 'Code non valable.');
  });
}
