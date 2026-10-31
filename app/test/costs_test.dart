import 'package:coupon_pro_ia/features/admin/presentation/costs_admin_screen.dart';
import 'package:coupon_pro_ia/features/billing/billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'costs_test_data.dart';

Widget _wrap(Widget child, {double scale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(400, 900), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  test('tailles lisibles', () {
    expect(bytesLabel(512), '512 o');
    expect(bytesLabel(48234496), '46,0 Mo');
    expect(bytesLabel(412000), '402,3 Ko');
  });

  testWidgets('coût par utilisateur actif et détail mesuré / renseigné',
      (tester) async {
    await tester.pumpWidget(_wrap(CostsView(data: costsSample)));
    expect(find.text(fcfa(1257)), findsOneWidget);
    expect(find.text('déficit'), findsOneWidget);
    expect(
        find.textContaining('Analyses de match : 18 appels'), findsOneWidget);
    expect(find.textContaining('Supabase : ${fcfa(15000)}'), findsOneWidget);
    expect(find.textContaining('non renseignés'), findsNothing);
  });

  testWidgets('abonnements fixes absents : avertissement', (tester) async {
    final d = {
      ...costsSample,
      'fixed': {
        'monthly_xof': 0,
        'period_xof': 0,
        'items': <String, dynamic>{},
        'configured': false,
      },
      'per_active_user_xof': null,
    };
    await tester.pumpWidget(_wrap(CostsView(data: d)));
    expect(find.textContaining('non renseignés'), findsOneWidget);
    expect(find.text('–'), findsWidgets);
  });

  testWidgets('texte ×1,6 sans débordement', (tester) async {
    await tester.pumpWidget(_wrap(CostsView(data: costsSample), scale: 1.6));
    expect(tester.takeException(), isNull);
  });
}
