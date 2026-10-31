import 'package:coupon_pro_ia/core/widgets/history_filter.dart';
import 'package:coupon_pro_ia/features/analysis/data/analysis_format.dart';
import 'package:coupon_pro_ia/features/analysis/data/analysis_repository.dart';
import 'package:coupon_pro_ia/features/analysis/data/match_reading.dart';
import 'package:coupon_pro_ia/features/home/home_screen.dart';
import 'package:coupon_pro_ia/features/matches/data/insights_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_repository.dart';
import 'package:coupon_pro_ia/features/matches/presentation/match_detail_screen.dart';
import 'package:coupon_pro_ia/features/matches/presentation/match_tabs.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:coupon_pro_ia/features/onboarding/data/preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/match_fixtures.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('langage courant', () {
    test('fréquences', () {
      expect(frequencyLabel(0.75), 'environ 3 fois sur 4');
      expect(frequencyLabel(0.17), 'environ 1 fois sur 6');
      expect(frequencyLabel(0.5), 'environ 1 fois sur 2');
      expect(frequencyLabel(0.258), 'environ 1 fois sur 4');
      expect(frequencyLabel(0.385), 'environ 2 fois sur 5');
      expect(frequencyLabel(0.64), 'environ 2 fois sur 3');
      expect(frequencyLabel(0.933), 'environ 19 fois sur 20');
      expect(frequencyLabel(0.03), 'moins d’1 fois sur 20');
      expect(frequencyLabel(0.99), 'plus de 19 fois sur 20');
      expect(frequencyLabel(0.548), 'environ 1 fois sur 2');
      expect(frequencyLabel(0.9), 'environ 9 fois sur 10');
    });

    test('cote juste', () {
      expect(fairOdd(0.5), 2);
      expect(fairOdd(0), isNull);
      expect(decimal(fairOdd(0.385)!), '2,60');
    });
  });

  group('lecture de l’analyse', () {
    test('pronostic de l’IA', () {
      final p = mainPickOf(lilleLensAnalysis())!;
      expect(p.key, '1X2.HOME');
      expect(p.fromAi, isTrue);
      expect(p.oddMedian, 2.7);
      expect(p.edge, closeTo(0.033, 1e-9));
    });

    test('sans recommandation : issue la plus probable, signalée comme telle',
        () {
      final p = mainPickOf(lilleLensAnalysis(recommend: false))!;
      expect(p.fromAi, isFalse);
      expect(p.key, '1X2.HOME');
      final s = mainPickOf(lilleLensAnalysis(withAi: false))!;
      expect(s.fromAi, isFalse);
    });

    test('issues contraires et encadré « Si ça ne passe pas »', () {
      final f = lilleLensAnalysis().fiche;
      expect(alternativesOf('1X2.HOME', f, 'Lille', 'Lens').map((e) => e.$1),
          ['Match nul', 'Victoire Lens']);
      expect(alternativesOf('DC.1X', f, 'Lille', 'Lens').single.$1,
          'Victoire Lens');
      expect(alternativesOf('OU.OVER.2.5', f, 'Lille', 'Lens').single.$1,
          'Moins de 2,5 buts');
      final text =
          downsideText(mainPickOf(lilleLensAnalysis())!, f, 'Lille', 'Lens');
      expect(text, contains('39 %'));
      expect(text, contains('environ 3 fois sur 5'));
      expect(text, contains('Match nul 26 %'));
      expect(forbiddenInText(text), isFalse);
    });

    test('faits vérifiés : chacun avec sa source', () {
      final facts = buildFacts(
        home: 'Lille',
        away: 'Lens',
        homeId: 79,
        awayId: 116,
        insights: lilleLensInsights(),
        analysis: lilleLensAnalysis(),
      );
      final titles = facts.map((f) => f.title).toList();
      expect(
          titles,
          containsAll([
            'Classement',
            'Forme récente',
            'Confrontations directes',
            'Buts attendus',
            'Le match nul',
            'Modèle et marché'
          ]));
      final rank = facts.firstWhere((f) => f.title == 'Classement');
      expect(rank.text, contains('Lille est 3e avec 15 points'));
      expect(rank.sourceLabel, startsWith('API-Football · 30/10'));
      final h2h = facts.firstWhere((f) => f.title == 'Confrontations directes');
      expect(h2h.text,
          contains('3 victoires de Lille, 0 nul, 1 victoire de Lens'));
      expect(facts.every((f) => f.source.isNotEmpty), isTrue);
      final streak = facts.firstWhere((f) => f.title == 'Série en cours');
      expect(streak.text, 'Lens : a marqué lors de 9 matchs de suite.');
    });

    test('faits sans analyse : uniquement les résultats enregistrés', () {
      final facts = buildFacts(
          home: 'Lille',
          away: 'Lens',
          homeId: 79,
          awayId: 116,
          insights: lilleLensInsights());
      expect(facts.any((f) => f.source.startsWith('Modèle')), isFalse);
      expect(facts, isNotEmpty);
    });
  });

  group('statistiques', () {
    test('zones et séries', () {
      final ins = lilleLensInsights();
      expect(ins.standingOf(79)!.zone, StandingZone.qualification);
      expect(ins.standings.first.zone, StandingZone.top);
      expect(ins.standings.last.zone, StandingZone.relegation);
      expect(zoneLabel('Promotion - Champions League (Qualification)'),
          'Qualification Ligue des champions');
      expect(zoneLabel('Relegation'), 'Zone de relégation');
      expect(formPoints(ins.homeForm), 5);
      expect(ins.h2h.matches[1].letterForMatchHome, 'D');
      final streaks = usefulStreaks([
        const Streak(key: 'wins', length: 4, atLeast: false),
        const Streak(key: 'unbeaten', length: 4, atLeast: false),
        const Streak(key: 'scored', length: 6, atLeast: true),
      ]);
      expect(streaks.map((s) => s.key), ['scored', 'wins']);
      expect(streaks.first.label, 'A marqué lors d’au moins 6 matchs de suite');
    });

    test('filtre d’historique : les pertes restent visibles par défaut', () {
      final now = DateTime(2026, 10, 30);
      const all = HistoryFilter();
      expect(all.accepts('lost', DateTime(2026, 1, 1), now: now), isTrue);
      const lost7 = HistoryFilter(result: ResultFilter.lost, days: 7);
      expect(lost7.accepts('lost', DateTime(2026, 10, 28), now: now), isTrue);
      expect(lost7.accepts('lost', DateTime(2026, 10, 1), now: now), isFalse);
      expect(lost7.accepts('won', DateTime(2026, 10, 28), now: now), isFalse);
      const pending = HistoryFilter(result: ResultFilter.pending);
      expect(pending.accepts(null, now, now: now), isTrue);
    });

    test('accueil : matchs mis en avant par priorité de compétition', () {
      MatchSummary m(int id, int priority, String status, String at) =>
          MatchSummary.fromJson({
            'id': id,
            'season': 2026,
            'kickoff_at': at,
            'status': status,
            'source_updated_at': at,
            'competition': {
              'id': priority,
              'name': 'C$priority',
              'priority': priority
            },
            'home': {'id': id * 10, 'name': 'A$id'},
            'away': {'id': id * 10 + 1, 'name': 'B$id'},
          });
      final list = highlightedMatches([
        m(1, 50, 'scheduled', '2026-10-30T20:00:00Z'),
        m(2, 5, 'scheduled', '2026-10-30T21:00:00Z'),
        m(3, 5, 'finished', '2026-10-30T12:00:00Z'),
        m(4, 5, 'scheduled', '2026-10-30T18:00:00Z'),
      ]);
      expect(list.map((x) => x.id), [4, 2, 1]);
      // Compétition suivie : passe devant, même moins prioritaire.
      final fav = highlightedMatches([
        m(1, 50, 'scheduled', '2026-10-30T20:00:00Z'),
        m(2, 5, 'scheduled', '2026-10-30T21:00:00Z'),
      ], favorites: {
        50
      });
      expect(fav.map((x) => x.id), [1, 2]);
      expect(longDate(DateTime(2026, 10, 30)), 'vendredi 30 octobre');
    });
  });

  group('écrans de la fiche match', () {
    final match = lilleLens();
    List<Override> overrides({bool analysis = true}) => [
          featureFlagsProvider
              .overrideWith((ref) async => {'match_analysis': true}),
          myPermissionsProvider.overrideWith((ref) async => <String>{}),
          myPreferencesProvider.overrideWith((ref) async => UserPreferences(
              level: UserLevel.expert, onboardedAt: DateTime(2026))),
          latestEvaluationProvider.overrideWith((ref) async => null),
          currentAnalysisProvider.overrideWith(
              (ref, id) => AsyncData(analysis ? lilleLensAnalysis() : null)),
          storedAnalysisProvider.overrideWith(
              (ref, id) async => analysis ? lilleLensAnalysis() : null),
          matchInsightsProvider
              .overrideWith((ref, id) async => lilleLensInsights()),
          featuredMatchProvider.overrideWith((ref) async => 5988),
          latestOddsProvider.overrideWith((ref, id) async => const []),
          market1x2OfMatchProvider.overrideWith((ref, id) async =>
              const Market1x2(
                  matchId: 5988,
                  pHome: 0.352,
                  pDraw: 0.286,
                  pAway: 0.362,
                  bookmakers: 10)),
        ];

    Future<void> pump(WidgetTester tester, Widget child,
        {bool analysis = true, double scale = 1}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(analysis: analysis),
        child: MaterialApp(
          home: Scaffold(body: child),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
        ),
      ));
      await tester.pumpAndSettle();
    }

    // Taille de texte maximale autorisée par l'app : aucun onglet ne déborde, jusqu'en bas.
    for (final (name, tab) in [
      ('Pronostic', PronosticTab(match: match)),
      ('Analyse', AnalysisTab(match: match)),
      ('Marchés', MarketsTab(match: match)),
      ('Stats', StatsTab(match: match)),
    ]) {
      testWidgets('$name en très grand texte, sans débordement',
          (tester) async {
        await pump(tester, tab, scale: 1.6);
        await tester.drag(
            find.byType(Scrollable).first, const Offset(0, -20000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Pronostic : pronostic de l’IA, cote juste, scores',
        (tester) async {
      await pump(tester, PronosticTab(match: match));
      expect(find.text('PRONOSTIC DE L’IA'), findsOneWidget);
      expect(find.text('Victoire Lille'), findsWidgets);
      expect(find.text('2,60'), findsOneWidget); // cote juste
      expect(find.text('2,70'), findsOneWidget); // cote du marché
      expect(find.text('environ 2 fois sur 5'), findsWidgets);
      expect(find.text('1-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Pronostic sans analyse : répartition selon les cotes et bouton',
        (tester) async {
      await pump(tester, PronosticTab(match: match), analysis: false);
      expect(find.text('Selon les cotes des bookmakers'), findsOneWidget);
      expect(find.text('Analyser avec l’IA'), findsOneWidget);
    });

    testWidgets(
        'Analyse : faits sourcés, lecture de l’IA, scénario défavorable',
        (tester) async {
      await pump(tester, AnalysisTab(match: match));
      expect(find.text('EN UNE PHRASE'), findsOneWidget);
      expect(find.text('Faits vérifiés'), findsOneWidget);
      expect(find.textContaining('API-Football · 30/10'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Si ça ne passe pas'), 300);
      expect(find.text('Si ça ne passe pas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Marchés : estimation, cote juste, cote, écart',
        (tester) async {
      await pump(tester, MarketsTab(match: match));
      expect(find.text('RÉSULTAT'), findsOneWidget);
      expect(find.text('Pronostic'), findsOneWidget);
      expect(find.text('+3 pts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Stats : classement, comparatif, séries, confrontations',
        (tester) async {
      await pump(tester, StatsTab(match: match));
      expect(find.text('3e'), findsWidgets);
      expect(find.text('Classement'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text('Confrontations directes'), 400);
      expect(find.text('Confrontations directes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('En-tête : forme et analyse offerte', (tester) async {
      await pump(tester, MatchHeader(match: match));
      expect(find.text('Analyse offerte du jour'), findsOneWidget);
      expect(find.text('V'), findsWidgets);
    });
  });
}

bool forbiddenInText(String t) => RegExp(r'(?<![\p{L}])(sûr|garanti|assuré)',
        unicode: true, caseSensitive: false)
    .hasMatch(t.replaceAll('aucun gain garanti', ''));
