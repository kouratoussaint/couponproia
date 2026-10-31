import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/brand_colors.dart';
import '../../analysis/data/analysis_format.dart';
import '../../analysis/data/analysis_repository.dart';
import '../../analysis/data/match_reading.dart';
import '../../analysis/presentation/analysis_section.dart';
import '../../lab/data/lab_repository.dart';
import '../../onboarding/data/preferences_repository.dart';
import '../../system/system_providers.dart';
import '../data/insights_models.dart';
import '../data/matchday_models.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'sports_widgets.dart';

export 'match_stats_tab.dart';

final market1x2OfMatchProvider =
    FutureProvider.autoDispose.family<Market1x2?, int>((ref, id) async {
  final map = await ref.watch(sportsRepositoryProvider).market1x2([id]);
  return map[id];
});

const _pad = EdgeInsets.fromLTRB(12, 8, 12, 32);

bool _analysisEnabled(WidgetRef ref) =>
    (ref.watch(featureFlagsProvider).valueOrNull ??
        const {})['match_analysis'] !=
    false;

// ---------------------------------------------------------------------------------------------
// Onglet Pronostic
// ---------------------------------------------------------------------------------------------
class PronosticTab extends ConsumerWidget {
  const PronosticTab({super.key, required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(currentAnalysisProvider(match.id));
    final home = match.home.name;
    final away = match.away.name;
    final played = match.hasScore &&
        (match.status == MatchStatus.finished ||
            match.status == MatchStatus.awarded);
    return ListView(
      padding: _pad,
      children: [
        if (!_analysisEnabled(ref))
          const NoticeCard(
              icon: Icons.pause_circle_outline,
              text: 'Les analyses sont momentanément désactivées.')
        else
          ...analysis.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(userMessageFor(e))],
            data: (a) {
              if (a == null) {
                return [
                  _MarketPreview(match: match),
                  const SizedBox(height: 12),
                  AnalyzeButton(match: match),
                  const SizedBox(height: 8),
                  Text(
                    'L’analyse donne l’estimation du modèle pour chaque issue, la cote juste, les scores '
                    'les plus probables et la lecture de l’IA, vérifiée chiffre par chiffre.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ];
              }
              final pick = mainPickOf(a);
              return [
                if (played) ActualResultNotice(fiche: a.fiche, match: match),
                if (pick != null)
                  MainPickCard(pick: pick, match: match, analysis: a),
                if (ref
                        .watch(myPreferencesProvider)
                        .valueOrNull
                        ?.showExplanations ??
                    true)
                  const GlossaryCard(),
                ProbabilitiesCard(fiche: a.fiche, home: home, away: away),
                ScoresCard(fiche: a.fiche, max: 3),
                const SizedBox(height: 8),
                AnalyzeButton(match: match),
                AnalysisFooter(analysis: a),
              ];
            },
          ),
        const ResponsibleNote(),
      ],
    );
  }
}

/// Avant l'analyse : la répartition selon les cotes, clairement présentée comme telle.
class _MarketPreview extends ConsumerWidget {
  const _MarketPreview({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final market = ref.watch(market1x2OfMatchProvider(match.id)).valueOrNull;
    if (market == null) {
      return const NoticeCard(
          icon: Icons.info_outline,
          text: 'Aucune cote relevée pour ce match pour l’instant.');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Selon les cotes des bookmakers',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
                'Probabilités implicites, marge des bookmakers retirée (${market.bookmakers} bookmakers au maximum). '
                'Ce n’est pas l’estimation du modèle.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            ProbabilityBar(
                label: 'Victoire ${match.home.name}',
                probability: market.pHome),
            ProbabilityBar(label: 'Match nul', probability: market.pDraw),
            ProbabilityBar(
                label: 'Victoire ${match.away.name}',
                probability: market.pAway),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Onglet Analyse
// ---------------------------------------------------------------------------------------------
class AnalysisTab extends ConsumerWidget {
  const AnalysisTab({super.key, required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analysis = ref.watch(currentAnalysisProvider(match.id)).valueOrNull;
    final insights = ref.watch(matchInsightsProvider(match.id)).valueOrNull;
    final home = match.home.name;
    final away = match.away.name;
    final facts = buildFacts(
      home: home,
      away: away,
      homeId: match.home.id,
      awayId: match.away.id,
      insights: insights,
      analysis: analysis,
    );
    final ai = analysis?.ai;
    final pick = analysis == null ? null : mainPickOf(analysis);
    return ListView(
      padding: _pad,
      children: [
        if (analysis == null) ...[
          const NoticeCard(
              icon: Icons.auto_awesome_outlined,
              text:
                  'La lecture de l’IA apparaît après « Analyser avec l’IA ». Les faits ci-dessous viennent '
                  'directement des résultats enregistrés.'),
          if (_analysisEnabled(ref)) AnalyzeButton(match: match),
        ] else
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('EN UNE PHRASE',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  if (pick != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${outcomeKeyLabel(pick.key, home, away)}'
                      '${pick.oddMedian == null ? '' : ' · cote ${decimal(pick.oddMedian!)}'}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    ai != null && ai.summary.isNotEmpty
                        ? ai.summary
                        : statsOnlyReason(analysis.statusReason),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        MatchdayCard(match: match),
        if (facts.isNotEmpty) ...[
          const SectionTitle('Faits vérifiés'),
          for (final f in facts) FactCard(fact: f),
        ] else if (insights == null)
          const Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (ai != null) ...[
          const SectionTitle('La lecture de l’IA'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ai.form.isNotEmpty)
                    TextBlock(title: 'La forme', body: ai.form),
                  if (ai.homeFactors.isNotEmpty)
                    TextBlock(title: 'Atouts de $home', items: ai.homeFactors),
                  if (ai.awayFactors.isNotEmpty)
                    TextBlock(title: 'Atouts de $away', items: ai.awayFactors),
                  if (ai.trends.isNotEmpty)
                    TextBlock(title: 'Tendances', items: ai.trends),
                  if (ai.picks.isNotEmpty)
                    TextBlock(
                      title: 'Pourquoi ces marchés',
                      items: [
                        for (final p in ai.picks)
                          '${outcomeKeyLabel(p.key, home, away)} (${pct(p.modelProbability)}) : ${p.justification}'
                      ],
                    ),
                  if (ai.risks.isNotEmpty)
                    TextBlock(
                        title: 'Ce qui peut tout changer',
                        items: ai.risks,
                        color: BrandColors.orange),
                  if (ai.conclusion.isNotEmpty)
                    TextBlock(title: 'Conclusion', body: ai.conclusion),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              'Chaque chiffre des textes de l’IA est vérifié automatiquement : il doit figurer dans la fiche '
              'du moteur. Les mots de certitude sont refusés.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
        if (analysis != null && pick != null) ...[
          const SectionTitle('Si ça ne passe pas'),
          NoticeCard(
              icon: Icons.info_outline,
              text: downsideText(pick, analysis.fiche, home, away)),
        ],
        if (analysis != null) ...[
          if (mergedMissing(analysis.fiche, ai).isNotEmpty) ...[
            const SectionTitle('Informations manquantes'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: TextBlock(
                    title: 'Non pris en compte',
                    items: mergedMissing(analysis.fiche, ai),
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          AnalysisFooter(analysis: analysis),
        ],
        const ResponsibleNote(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Onglet Marchés
// ---------------------------------------------------------------------------------------------
class MarketsTab extends ConsumerWidget {
  const MarketsTab({super.key, required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(currentAnalysisProvider(match.id)).valueOrNull;
    final pick = analysis == null ? null : mainPickOf(analysis);
    return ListView(
      padding: _pad,
      children: [
        if (analysis == null)
          const NoticeCard(
              icon: Icons.query_stats,
              text:
                  'L’estimation du modèle pour chaque marché (cote juste, écart avec le marché) apparaît '
                  'après l’analyse, dans l’onglet Pronostic.')
        else ...[
          if (analysis.fiche.comparableLines.isEmpty)
            const NoticeCard(
                icon: Icons.info_outline,
                text: 'Pas de cotes comparables au moment de l’analyse.')
          else
            MarketsComparison(
                fiche: analysis.fiche,
                home: match.home.name,
                away: match.away.name,
                highlightKey: pick?.fromAi == true ? pick!.key : null),
          ScoresCard(fiche: analysis.fiche),
        ],
        const SectionTitle('Toutes les cotes'),
        OddsBoard(match: match),
        const ResponsibleNote(),
      ],
    );
  }
}

/// Cotes relevées (médiane et meilleure), touchables pour composer un coupon.
class OddsBoard extends ConsumerWidget {
  const OddsBoard({super.key, required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final odds = ref.watch(latestOddsProvider(match.id));
    final picks = ref.watch(manualCouponProvider);
    final canPick = match.status == MatchStatus.scheduled &&
        match.kickoffAt.isAfter(DateTime.now());
    return odds.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(userMessageFor(e)),
      data: (list) {
        if (list.isEmpty) {
          return const NoticeCard(
            icon: Icons.info_outline,
            text:
                'Aucune cote relevée pour ce match. Les cotes sont relevées plusieurs fois par jour '
                'pour les matchs à venir.',
          );
        }
        final byMarket = oddsByMarket(list);
        final latest = list
            .map((o) => o.capturedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final books =
            list.map((o) => o.bookmakers).reduce((a, b) => a > b ? a : b);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in byMarket.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(marketTitles[entry.key] ?? entry.key,
                        style: theme.textTheme.labelLarge),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in entry.value)
                        _OddTile(
                          odd: o,
                          selected: picks.any((p) =>
                              p.matchId == match.id && p.key == oddsKey(o)),
                          onTap: canPick
                              ? () => ref
                                  .read(manualCouponProvider.notifier)
                                  .toggle(ManualPick(
                                    matchId: match.id,
                                    key: oddsKey(o),
                                    matchLabel:
                                        '${match.home.name} – ${match.away.name}',
                                    label:
                                        '${marketTitles[o.marketCode] ?? o.marketCode} : ${outcomeLabel(o)}',
                                    odd: o.median,
                                  ))
                              : null,
                        )
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (canPick)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Touchez une cote pour l’ajouter à votre coupon.',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                SourceChip(
                    label:
                        'Cote médiane de $books bookmakers au maximum · relevé ${shortDate(latest)} ${timeLabel(latest)}'),
                const SizedBox(height: 6),
                Text(
                  '« max » = meilleure cote relevée. Les cotes changent et peuvent différer de celles de votre opérateur.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OddTile extends StatelessWidget {
  const _OddTile({required this.odd, this.selected = false, this.onTap});

  final OddsLine odd;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(outcomeLabel(odd),
                style: theme.textTheme.labelMedium,
                overflow: TextOverflow.ellipsis),
            Text(formatOdd(odd.median),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.primary)),
            Text('max ${formatOdd(odd.best)}',
                style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// Couleur de chaque équipe dans les comparatifs (constante dans toute la fiche).
Color teamColor(bool home) => home ? BrandColors.vertIA : BrandColors.orange;

/// Définitions des termes (masquées pour un utilisateur qui se déclare expert).
class GlossaryCard extends StatelessWidget {
  const GlossaryCard({super.key});

  static const entries = [
    (
      'Estimation du modèle',
      'La probabilité calculée par notre modèle à partir des résultats enregistrés. '
          'C’est une estimation, pas une certitude.'
    ),
    (
      'Cote juste',
      'La cote qui correspondrait exactement à l’estimation (1 ÷ probabilité). '
          'Une cote du marché plus haute que la cote juste est plus intéressante.'
    ),
    (
      'Écart',
      'La différence entre l’estimation du modèle et celle du marché (cotes, marge retirée).'
    ),
    (
      'Fiabilité',
      'Dépend du nombre de matchs enregistrés pour chaque équipe : peu de matchs, estimation moins solide.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.help_outline, color: theme.colorScheme.primary),
          title: const Text('Comprendre ces chiffres'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (term, text) in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '$term : ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: text),
                ])),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compositions officielles et absents annoncés (API-Football), avec l'heure du relevé.
class MatchdayCard extends ConsumerWidget {
  const MatchdayCard({super.key, required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = ref.watch(matchdayProvider(match.id));
    final started = match.status != MatchStatus.scheduled;
    return data.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (d) {
        Widget team(TeamRef t) {
          final lineup = d.lineupOf(t.id);
          final absent = d.absencesOf(t.id);
          final out = [
            for (final a in absent)
              if (!a.uncertain) a
          ];
          final doubt = [
            for (final a in absent)
              if (a.uncertain) a
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (lineup != null) ...[
                Text(
                  [
                    if (lineup.formation != null) lineup.formation!,
                    if (lineup.coach != null) 'entraîneur ${lineup.coach}'
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                for (final p in lineup.startXI)
                  Text('${p.number ?? '–'}  ${p.name}',
                      style: theme.textTheme.bodyMedium),
              ],
              if (out.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Absents',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: BrandColors.rouge)),
                for (final a in out)
                  Text('${a.player} : ${absenceReason(a.reason)}',
                      style: theme.textTheme.bodySmall),
              ],
              if (doubt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Incertains',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: BrandColors.orange)),
                for (final a in doubt)
                  Text('${a.player} : ${absenceReason(a.reason)}',
                      style: theme.textTheme.bodySmall),
              ],
              if (lineup == null && absent.isEmpty)
                Text('Aucun absent annoncé',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          );
        }

        final hasLineups = d.lineups.isNotEmpty;
        final checked = d.lastFetched;
        if (!hasLineups && d.absences.isEmpty && checked == null && started) {
          return const SizedBox.shrink();
        }
        final expected = match.kickoffAt.subtract(const Duration(minutes: 40));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Compositions et absents'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!hasLineups && !started)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 18, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Compositions officielles attendues vers ${timeLabel(expected)} '
                                '(20 à 40 minutes avant le coup d’envoi).',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (checked == null)
                      Text(
                          'Absents pas encore vérifiés : la vérification commence 6 heures avant le match.',
                          style: theme.textTheme.bodySmall)
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: team(match.home)),
                          const SizedBox(width: 12),
                          Expanded(child: team(match.away)),
                        ],
                      ),
                    if (checked != null) ...[
                      const SizedBox(height: 10),
                      Text('API-Football · relevé à ${timeLabel(checked)}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
