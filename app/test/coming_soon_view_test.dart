import 'package:coupon_pro_ia/core/widgets/coming_soon_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('un module à venir affiche son lot et aucune donnée fictive',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComingSoonView(
            icon: Icons.sports_soccer,
            title: 'Matchs et analyses',
            lot: 'LOT 2',
            description: 'Rencontres réelles.',
            features: ['Matchs du jour'],
          ),
        ),
      ),
    );

    expect(find.text('Matchs et analyses'), findsOneWidget);
    expect(find.text('Prévu au LOT 2'), findsOneWidget);
    expect(find.text('Matchs du jour'), findsOneWidget);
  });
}
