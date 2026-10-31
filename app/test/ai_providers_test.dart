import 'package:coupon_pro_ia/features/admin/data/ai_providers_repository.dart';
import 'package:coupon_pro_ia/features/admin/presentation/ai_providers_screen.dart';
import 'package:coupon_pro_ia/features/analysis/data/analysis_models.dart';
import 'package:coupon_pro_ia/features/analysis/presentation/analysis_section.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final providersSample = [
  AiProviderInfo.fromJson({
    'name': 'gemini',
    'label': 'Gemini',
    'secret': 'GEMINI_API_KEY',
    'configured': true,
    'role': 'primary',
    'model': 'gemini-3.5-flash-lite',
    'usage': {
      'today': {'calls': 12, 'success': 11, 'rejected': 1},
      'days_7': {
        'calls': 68,
        'success': 66,
        'rejected': 2,
        'cost_usd': 0.12,
        'avg_latency_ms': 2400,
        'input_tokens': 126000,
        'output_tokens': 30600,
      },
      'days_30': {'calls': 68},
      'last_call': {'at': '2026-10-31T18:02:00Z', 'status': 'success'},
    },
  }),
  AiProviderInfo.fromJson({
    'name': 'groq',
    'label': 'Groq',
    'secret': 'GROQ_API_KEY',
    'configured': true,
    'role': 'fallback_2',
    'model': 'openai/gpt-oss-120b',
    'usage': null,
    'reference_limits': {
      'requests_per_minute': 30,
      'requests_per_day': 1000,
      'tokens_per_day': 200000
    },
  }),
  AiProviderInfo.fromJson({
    'name': 'anthropic',
    'label': 'Claude',
    'secret': 'ANTHROPIC_API_KEY',
    'configured': false,
    'role': 'fallback_1',
    'model': 'claude-haiku-5-5',
  }),
];

Widget _screen(Set<String> perms, {double scale = 1}) => ProviderScope(
      overrides: [
        myPermissionsProvider.overrideWith((ref) async => perms),
        aiProvidersProvider.overrideWith((ref) async => providersSample),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(400, 900), textScaler: TextScaler.linear(scale)),
          child: const AiProvidersScreen(),
        ),
      ),
    );

void main() {
  test('rôles : échange quand un rôle déjà pris est attribué', () {
    final roles = {
      'gemini': AiRole.primary,
      'groq': AiRole.fallback1,
      'anthropic': AiRole.disabled,
    };
    final swapped = assignRole(roles, 'groq', AiRole.primary);
    expect(swapped['groq'], AiRole.primary);
    expect(swapped['gemini'], AiRole.fallback1);
    expect(orderOf(swapped).primary, 'groq');
    expect(orderOf(swapped).fallbacks, ['gemini']);
    final off = assignRole(roles, 'gemini', AiRole.disabled);
    expect(orderOf(off).primary, isNull);
    expect(off['groq'], AiRole.fallback1);
  });

  testWidgets('écran : ordre d’appel, consommation, quota de référence',
      (tester) async {
    await tester.pumpWidget(_screen({'ai.providers'}));
    await tester.pumpAndSettle();
    expect(find.text('Ordre d’appel : Gemini → Claude → Groq'), findsOneWidget);
    expect(find.text('68'), findsOneWidget);
    expect(find.text('2,4 s'), findsOneWidget);
    expect(find.text('0,12 \$'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('0 / 1\u202f000'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('0 / 1\u202f000'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('Clé absente : ajoutez ANTHROPIC_API_KEY'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Clé absente : ajoutez ANTHROPIC_API_KEY'),
        findsOneWidget);
    // Rien à enregistrer tant que rien n'a changé.
    await tester.scrollUntilVisible(
        find.text('Enregistrer les changements'), 300,
        scrollable: find.byType(Scrollable).first);
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Enregistrer les changements'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('écran réservé au super administrateur', (tester) async {
    await tester.pumpWidget(_screen({'admin.access', 'ai.configure'}));
    await tester.pumpAndSettle();
    expect(find.text('Écran réservé au super administrateur'), findsOneWidget);
  });

  testWidgets('écran : texte ×1,6 sans débordement', (tester) async {
    await tester.pumpWidget(_screen({'ai.providers'}, scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pronostic : modèle et marché côte à côte, avec l’écart',
      (tester) async {
    final fiche = AnalysisFiche.fromJson({
      'engine_version': 'poisson-1.1',
      'reliability': 'moyenne',
      'model': {
        'expected_goals_home': 1.2,
        'expected_goals_away': 1.4,
        'probabilities': {'1X2.HOME': 0.30, '1X2.DRAW': 0.28, '1X2.AWAY': 0.42},
      },
      'market': {
        'captured_at': '2026-10-31T18:00:00Z',
        'lines': [
          for (final (k, p) in [
            ('1X2.HOME', 0.33),
            ('1X2.DRAW', 0.28),
            ('1X2.AWAY', 0.39)
          ])
            {
              'key': k,
              'odd_median': 1 / p,
              'odd_best': 1 / p,
              'bookmakers': 10,
              'implied_probability': p
            },
        ],
      },
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModelMarketCard(fiche: fiche, home: 'Liverpool', away: 'Arsenal'),
      ),
    ));
    expect(find.text('Modèle et marché'), findsOneWidget);
    expect(find.text('−3 pts modèle'), findsOneWidget);
    expect(find.text('identique'), findsOneWidget);
    expect(find.text('+3 pts modèle'), findsOneWidget);
    expect(find.textContaining('de 10 bookmakers, marge retirée, relevées le'),
        findsOneWidget);
  });
}
