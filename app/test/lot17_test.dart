// Lot 17 : hors connexion, rapports d'erreurs, santé de l'application, alertes personnalisées.
import 'dart:convert';
import 'dart:io';

import 'package:coupon_pro_ia/core/monitoring/error_reporter.dart';
import 'package:coupon_pro_ia/core/offline/offline_banner.dart';
import 'package:coupon_pro_ia/core/offline/offline_http_client.dart';
import 'package:coupon_pro_ia/core/offline/offline_store.dart';
import 'package:coupon_pro_ia/features/admin/presentation/health_admin_screen.dart';
import 'package:coupon_pro_ia/features/notifications/data/notifications_repository.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(String sub) {
  String part(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': sub})}.sig';
}

http.Request _get(String path, {String user = 'u1'}) =>
    http.Request('GET', Uri.parse('https://x.supabase.co/rest/v1/$path'))
      ..headers['Authorization'] = 'Bearer ${_jwt(user)}';

void main() {
  group('lecture hors connexion', () {
    setUp(() => offlineSince.value = null);

    test('réponse enregistrée puis resservie sans réseau', () async {
      final store = MemoryOfflineStore();
      var online = true;
      final inner = MockClient((req) async {
        if (!online) throw const SocketException('pas de réseau');
        return http.Response('[{"id":1}]', 200,
            headers: {'content-type': 'application/json'});
      });
      final client = OfflineHttpClient(inner, store);
      final first = await client.send(_get('coupons?select=*'));
      expect(await first.stream.bytesToString(), '[{"id":1}]');
      await Future<void>.delayed(Duration.zero);
      expect(store.values, hasLength(1));
      online = false;
      final again = await client.send(_get('coupons?select=*'));
      expect(again.statusCode, 200);
      expect(again.headers['x-offline-cache'], '1');
      expect(await again.stream.bytesToString(), '[{"id":1}]');
      expect(offlineSince.value, isNotNull);
      online = true;
      await client.send(_get('coupons?select=*'));
      expect(offlineSince.value, isNull);
    });

    test('jamais partagé entre deux comptes', () async {
      final store = MemoryOfflineStore();
      var online = true;
      final client = OfflineHttpClient(MockClient((req) async {
        if (!online) throw const SocketException('x');
        return http.Response('[]', 200);
      }), store);
      await client.send(_get('bet_journal', user: 'alice'));
      await Future<void>.delayed(Duration.zero);
      online = false;
      expect(() => client.send(_get('bet_journal', user: 'bob')),
          throwsA(isA<SocketException>()));
    });

    test('écritures et fonctions non listées : jamais en cache', () {
      final post = http.Request(
          'POST', Uri.parse('https://x.supabase.co/rest/v1/rpc/journal_add'));
      final read = http.Request('POST',
          Uri.parse('https://x.supabase.co/rest/v1/rpc/platform_performance'));
      final edge = http.Request(
          'GET', Uri.parse('https://x.supabase.co/functions/v1/assistant'));
      expect(OfflineHttpClient.cacheable(post), isFalse);
      expect(OfflineHttpClient.cacheable(read), isTrue);
      expect(OfflineHttpClient.cacheable(edge), isFalse);
      expect(OfflineHttpClient.userOf({'Authorization': 'Bearer ${_jwt('z')}'}),
          'z');
      expect(OfflineHttpClient.userOf(const {}), 'anon');
    });

    test('requête lente signalée sans paramètres', () async {
      String? path;
      final client = OfflineHttpClient(
          MockClient((req) async => http.Response('[]', 200)),
          MemoryOfflineStore(),
          slowThreshold: Duration.zero,
          onSlow: (p, _) => path = p);
      await client.send(_get('coupons?user_id=eq.secret'));
      expect(path, '/coupons');
    });

    test('bandeau : date des données', () {
      final now = DateTime(2026, 11, 1, 18);
      expect(OfflineBanner.label(DateTime(2026, 11, 1, 9, 5), now),
          'Hors connexion · données de 09:05');
      expect(OfflineBanner.label(DateTime(2026, 10, 31, 22, 0), now),
          'Hors connexion · données du 31/10 à 22:00');
    });
  });

  group('rapports d’erreurs', () {
    test('une fois par empreinte, réseau ignoré, désactivable', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sent = <ErrorReport>[];
      final r = ErrorReporter(prefs, send: (x) async => sent.add(x));
      final stack = StackTrace.current;
      r.record('dart', StateError('boom'), stack);
      r.record('dart', StateError('boom'), stack);
      r.record('dart', const SocketException('x'), null);
      r.recordSlow('/coupons', const Duration(seconds: 9));
      expect(r.queue, hasLength(2));
      await r.flush();
      expect(sent, hasLength(2));
      expect(sent.last.message, 'Requête lente : 9.0 s');
      await r.setEnabled(false);
      r.record('dart', StateError('autre'), null);
      expect(r.queue, isEmpty);
    });

    test('envoi impossible : gardé pour plus tard', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final r = ErrorReporter(prefs,
          send: (_) async => throw StateError('hors ligne'));
      r.record('flutter', StateError('a'), null);
      await r.flush();
      expect(r.queue, hasLength(1));
    });
  });

  group('alertes personnalisées', () {
    test('préférences lues, « tous » par défaut', () {
      final p = NotificationPrefs.fromJson({
        'notify_live': false,
        'coupon_categories': ['prudent', 'du_jour'],
      });
      expect(p.live, isFalse);
      expect(p.analyses, isTrue);
      expect(prefValue(p, 'notify_live'), isFalse);
      expect(p.couponCategories, {'prudent', 'du_jour'});
      expect(const NotificationPrefs().couponCategories, isEmpty);
      expect(
          notificationKinds.map((k) => k.$1),
          containsAll(
              ['notify_analyses', 'notify_bet_reminders', 'notify_live']));
    });
  });

  group('santé de l’application', () {
    testWidgets('alertes en cours et plantages', (tester) async {
      tester.view.physicalSize = const Size(420, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now().toUtc().toIso8601String();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          myPermissionsProvider.overrideWith((ref) async => {'ops.monitor'}),
          opsAlertsProvider.overrideWith((ref) async => [
                OpsAlert.fromJson({
                  'id': 1,
                  'severity': 'critical',
                  'title': 'IA indisponible',
                  'body': '3 erreurs',
                  'route': '/admin/ia',
                  'opened_at': now
                }),
                OpsAlert.fromJson({
                  'id': 2,
                  'severity': 'warning',
                  'title': 'Paiements en attente',
                  'body': '1 paiement',
                  'opened_at': now,
                  'resolved_at': now
                }),
              ]),
          clientErrorsProvider.overrideWith((ref) async => [
                ClientError.fromJson({
                  'id': 5,
                  'kind': 'dart',
                  'message': 'Null check operator',
                  'occurrences': 12,
                  'user_ids': ['a', 'b'],
                  'app_version': '0.24.0',
                  'first_seen': now,
                  'last_seen': now,
                  'context': '/accueil'
                }),
              ]),
        ],
        child: const MaterialApp(home: HealthAdminScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Alertes en cours (1)'), findsOneWidget);
      expect(find.text('IA indisponible'), findsOneWidget);
      expect(find.text('Alertes closes récemment'), findsOneWidget);
      expect(find.text('Null check operator'), findsOneWidget);
      expect(find.textContaining('12 fois · 2 utilisateurs · v0.24.0'),
          findsOneWidget);
    });
  });
}
