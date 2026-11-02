import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../simulator/presentation/sim_entries.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/solid_buttons.dart';
import '../../billing/credit_costs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/super_admin_note.dart';
import '../../lab/data/lab_repository.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/data/sports_models.dart';
import '../../system/system_providers.dart';
import '../data/analysis_format.dart';
import '../data/analysis_models.dart';
import '../data/analysis_repository.dart';
import '../data/match_reading.dart';
import 'analyze_access.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

// Composants de la fiche match (onglets Pronostic, Analyse, Marchés). Chaque chiffre vient de la
// fiche du moteur ; les textes de l'IA ont été vérifiés par le serveur.

bool isAnalyzable(MatchSummary m) => !{
      MatchStatus.postponed,
      MatchStatus.cancelled,
      MatchStatus.abandoned
    }.contains(m.status);

/// Bouton « Analyser avec l'IA » / « Mettre à jour l'analyse ».
class AnalyzeButton extends ConsumerStatefulWidget {
  const AnalyzeButton({super.key, required this.match, this.compact = false});

  final MatchSummary match;
  final bool compact;

  @override
  ConsumerState<AnalyzeButton> createState() => _AnalyzeButtonState();
}

class _AnalyzeButtonState extends ConsumerState<AnalyzeButton> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Ouvert depuis le bouton « Analyser » d'une liste : l'analyse démarre seule.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(autoAnalyzeProvider) != widget.match.id) return;
      ref.read(autoAnalyzeProvider.notifier).state = null;
      final has =
          ref.read(currentAnalysisProvider(widget.match.id)).valueOrNull;
      if (has == null && ref.read(analysisAllowedProvider(widget.match.id))) {
        _run();
      }
    });
  }

  Future<void> _run({bool force = false}) async {
    setState(() => _running = true);
    try {
      final result = await ref
          .read(analysisRepositoryProvider)
          .analyze(widget.match.id, force: force);
      ref.read(freshAnalysisProvider(widget.match.id).notifier).state = result;
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is AnalysisException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final analysis = ref.watch(currentAnalysisProvider(match.id)).valueOrNull;
    final isAdmin =
        (ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{})
            .contains('ai.configure');
    final played = match.status == MatchStatus.finished ||
        match.status == MatchStatus.awarded;
    final canRefresh = analysis == null || analysis.status != 'ok' || !played;

    if (!isAnalyzable(match)) {
      return FilledButton.tonal(
          onPressed: null,
          child: Text(tr('Analyse indisponible (match reporté ou annulé)')));
    }
    if (_running) {
      return FilledButton.tonal(
        onPressed: null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text(tr('Analyse en cours…')),
          ],
        ),
      );
    }
    final allowed = ref.watch(analysisAllowedProvider(match.id));
    // Analyse déjà visible : l'accès est acquis, la mise à jour reste gratuite.
    if (analysis == null && !allowed) {
      return FilledButton.icon(
        style: solidButtonStyle(context, SolidTone.red),
        onPressed: () => showAnalysisLocked(context),
        icon: const Icon(Icons.lock_outline),
        label: Text(tr('Analyse réservée : forfait payant ou crédits')),
      );
    }
    if (analysis == null) {
      final cost = ref.watch(analysisChargeProvider(match.id));
      return FilledButton.icon(
        style: solidButtonStyle(context, SolidTone.green),
        onPressed: _run,
        icon: const Icon(Icons.auto_awesome),
        label: Text(cost > 0
            ? trf('Analyser avec l’IA · {0}', [creditsLabel(cost)])
            : tr('Analyser avec l’IA')),
      );
    }
    return Row(
      children: [
        if (canRefresh)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Mettre à jour l’analyse')),
            ),
          ),
        if (isAdmin) ...[
          if (canRefresh) const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: tr('Régénérer (administrateur)'),
            onPressed: () => _run(force: true),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ],
    );
  }
}

class ReliabilityChip extends StatelessWidget {
  const ReliabilityChip({super.key, required this.reliability});

  final Reliability reliability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (reliability) {
      Reliability.bonne => scheme.primary,
      Reliability.moyenne => BrandColors.orange,
      Reliability.faible => scheme.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(reliabilityLabel(reliability),
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Encadré d'information neutre.
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// Petite case chiffrée (« Estimation du modèle 75 % »).
class StatCell extends StatelessWidget {
  const StatCell(
      {super.key,
      required this.label,
      required this.value,
      this.caption,
      this.highlight = false});

  final String label;
  final String value;
  final String? caption;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: highlight
            ? Border.all(color: scheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: highlight ? scheme.primary : null)),
          if (caption != null)
            Text(caption!,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Carte « pronostic principal » : issue, estimation, cote juste, cote du marché, justification.
class MainPickCard extends ConsumerWidget {
  const MainPickCard(
      {super.key,
      required this.pick,
      required this.match,
      required this.analysis});

  final MainPick pick;
  final MatchSummary match;
  final MatchAnalysis analysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = outcomeKeyLabel(pick.key, match.home.name, match.away.name);
    final picks = ref.watch(manualCouponProvider);
    final selected =
        picks.any((p) => p.matchId == match.id && p.key == pick.key);
    final canPick = pick.oddMedian != null &&
        match.status == MatchStatus.scheduled &&
        match.kickoffAt.isAfter(DateTime.now());
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pick.fromAi
                        ? tr('PRONOSTIC DE L’IA')
                        : tr('ISSUE LA PLUS PROBABLE (MODÈLE)'),
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1),
                  ),
                ),
                ReliabilityChip(reliability: analysis.fiche.reliability),
              ],
            ),
            const SizedBox(height: 10),
            Text(label,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCell(
                    label: tr('Estimation du modèle'),
                    value: pct(pick.probability),
                    caption: frequencyLabel(pick.probability),
                    highlight: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCell(
                    label: tr('Cote juste'),
                    value: decimal(pick.fairOddValue),
                    caption: tr('1 ÷ estimation'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCell(
                    label: tr('Cote du marché'),
                    value:
                        pick.oddMedian == null ? '—' : decimal(pick.oddMedian!),
                    caption: pick.edge == null
                        ? tr('non relevée')
                        : trf('écart {0}', [edgePoints(pick.edge!)]),
                  ),
                ),
              ],
            ),
            if ((pick.justification ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(pick.justification!, style: theme.textTheme.bodyLarge),
            ],
            if (!pick.fromAi) ...[
              const SizedBox(height: 10),
              Text(
                analysis.ai != null && !analysis.ai!.recommendationPossible
                    ? tr(
                        'L’IA ne retient aucun pronostic pour ce match (données insuffisantes ou estimation trop fragile). Ci-dessus, l’issue la plus probable selon le modèle, à titre d’information.')
                    : tr(
                        'Issue la plus probable selon le modèle, sans recommandation de l’IA.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (pick.oddMedian != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: SimulateButton(
                    choices: () => [
                          singleSim(match,
                              key: pick.key,
                              odd: pick.oddMedian!,
                              probability: pick.probability)
                        ]),
              ),
            ],
            if (canPick) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => ref
                      .read(manualCouponProvider.notifier)
                      .toggle(ManualPick(
                        matchId: match.id,
                        key: pick.key,
                        matchLabel: '${match.home.name} – ${match.away.name}',
                        label: label,
                        odd: pick.oddMedian!,
                      )),
                  icon: Icon(selected ? Icons.check : Icons.add),
                  label: Text(selected
                      ? tr('Dans mon coupon')
                      : tr('Ajouter à mon coupon')),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              trf(
                  'La cote du marché est la cote médiane relevée{0} ; elle peut bouger avant le match. La cote juste n’est pas une promesse : c’est la cote qui correspond à l’estimation du modèle.',
                  [
                    analysis.fiche.marketCapturedAt == null
                        ? ''
                        : trf(' le {0} à {1}', [
                            shortDate(analysis.fiche.marketCapturedAt!),
                            timeLabel(analysis.fiche.marketCapturedAt!)
                          ])
                  ]),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre de probabilité avec libellé, pourcentage et fréquence en clair.
class ProbabilityBar extends StatelessWidget {
  const ProbabilityBar(
      {super.key,
      required this.label,
      required this.probability,
      this.highlight = false});

  final String label;
  final double probability;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis)),
              Text(pct(probability),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: highlight ? color : null)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: probability.clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 2),
          Text(frequencyLabel(probability),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Probabilités du résultat : estimation du modèle et marché côte à côte, avec l'écart.
/// Le marché vient des cotes relevées pour l'analyse ; à défaut, des cotes actuelles.
class ModelMarketCard extends StatelessWidget {
  const ModelMarketCard(
      {super.key,
      required this.fiche,
      required this.home,
      required this.away,
      this.liveMarket});

  final AnalysisFiche fiche;
  final String home;
  final String away;

  /// Probabilités 1-N-2 actuelles (marge retirée), utilisées si l'analyse n'en a pas.
  final ({
    double home,
    double draw,
    double away,
    int bookmakers,
    DateTime? at
  })? liveMarket;

  static const keys = ['1X2.HOME', '1X2.DRAW', '1X2.AWAY'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fiche;
    final lines = {
      for (final l in f.marketLines)
        if (keys.contains(l.key) && l.impliedProbability != null) l.key: l
    };
    final fromFiche = lines.length == 3;
    final live = liveMarket;
    double? market(String k) {
      if (fromFiche) return lines[k]!.impliedProbability;
      if (live == null) return null;
      return switch (k) {
        '1X2.HOME' => live.home,
        '1X2.DRAW' => live.draw,
        _ => live.away,
      };
    }

    final bookmakers = fromFiche
        ? lines.values.map((l) => l.bookmakers).reduce((a, b) => a > b ? a : b)
        : live?.bookmakers;
    final at = fromFiche ? f.marketCapturedAt : live?.at;
    final hasMarket = fromFiche || live != null;
    final modelColor = theme.colorScheme.primary;
    final marketColor = theme.brightness == Brightness.dark
        ? const Color(0xFF8FA3FF)
        : BrandColors.bleuTech;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(
                        hasMarket
                            ? tr('Modèle et marché')
                            : tr('Résultat du match selon le modèle'),
                        style: theme.textTheme.labelLarge)),
                if (hasMarket) ...[
                  _Legend(color: modelColor, label: tr('Modèle')),
                  const SizedBox(width: 10),
                  _Legend(color: marketColor, label: tr('Marché')),
                ],
              ],
            ),
            const SizedBox(height: 8),
            for (final k in keys)
              if (f.p(k) != null)
                _OutcomeRows(
                  label: outcomeKeyLabel(k, home, away),
                  model: f.p(k)!,
                  market: market(k),
                  modelColor: modelColor,
                  marketColor: marketColor,
                ),
            const SizedBox(height: 6),
            Text(
              trf('Buts attendus : {0} {1} – {2} {3}', [
                home,
                decimal(f.expectedGoalsHome),
                decimal(f.expectedGoalsAway),
                away
              ]),
              style: theme.textTheme.bodyMedium,
            ),
            if (hasMarket) ...[
              const SizedBox(height: 6),
              Text(
                trf(
                    'Marché : cotes médianes{0}, marge retirée{1}. Ce sont aussi des estimations.',
                    [
                      bookmakers == null || bookmakers == 0
                          ? ''
                          : trf(' de {0} bookmaker{1}',
                              [bookmakers, bookmakers > 1 ? 's' : '']),
                      at == null
                          ? ''
                          : trf(', relevées le {0} à {1}', [
                              shortDate(at.toLocal()),
                              timeLabel(at.toLocal())
                            ])
                    ]),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _OutcomeRows extends StatelessWidget {
  const _OutcomeRows(
      {required this.label,
      required this.model,
      required this.market,
      required this.modelColor,
      required this.marketColor});

  final String label;
  final double model;
  final double? market;
  final Color modelColor;
  final Color marketColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = market;
    final diff = m == null ? null : ((model - m) * 100).round();
    Widget bar(double p, Color c, {bool muted = false}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                    color: c,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(pct(p),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color:
                            muted ? theme.colorScheme.onSurfaceVariant : null,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis)),
              if (diff != null)
                Text(
                    diff == 0
                        ? 'identique'
                        : trf('{0}{1} pt{2} modèle', [
                            diff > 0 ? '+' : '−',
                            diff.abs(),
                            diff.abs() > 1 ? 's' : ''
                          ]),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          bar(model, modelColor),
          if (m != null) bar(m, marketColor, muted: true),
        ],
      ),
    );
  }
}

/// Scores exacts les plus probables (modèle de buts).
class ScoresCard extends StatelessWidget {
  const ScoresCard({super.key, required this.fiche, this.max = 5});

  final AnalysisFiche fiche;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scores = fiche.topScores.take(max).toList();
    if (scores.isEmpty) return const SizedBox.shrink();
    final covered = scores.fold<double>(0, (s, x) => s + x.probability);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Scores exacts les plus probables'),
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in scores)
                  Container(
                    width: 74,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(s.score,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(pct(s.probability),
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trf('Ces {0} scores couvrent {1} des cas selon le modèle : un score exact reste très incertain.',
                  [scores.length, pct(covered)]),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

final marketFamilies = [
  ('1X2', tr('Résultat')),
  ('DC', tr('Double chance')),
  ('OU', tr('Nombre de buts')),
  ('BTTS', tr('Les deux équipes marquent')),
  ('DNB', tr('Remboursé si nul')),
  ('TTH', tr('Buts de l’équipe à domicile')),
  ('TTA', tr('Buts de l’équipe à l’extérieur')),
];

/// Famille d'évaluation d'un marché (la double chance suit le 1X2, les buts par équipe → TT).
String qualityFamily(String code) => switch (code) {
      'DC' => '1X2',
      'TTH' || 'TTA' => 'TT',
      _ => code,
    };

/// Marchés du match : estimation du modèle, cote juste, cote du marché, écart.
class MarketsComparison extends StatelessWidget {
  const MarketsComparison(
      {super.key,
      required this.fiche,
      required this.home,
      required this.away,
      this.highlightKey,
      this.onSimulate});

  final AnalysisFiche fiche;
  final String home;
  final String away;
  final String? highlightKey;

  /// Touché sur une ligne : ouvre le simulateur de mise pour cette issue.
  final void Function(FicheOddsLine line)? onSimulate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fiche;
    final lines = f.comparableLines;
    final weak = f.weakGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (code, title) in marketFamilies)
          if (lines.any((l) => l.key.startsWith('$code.')))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800, letterSpacing: 1)),
                    if (!f.beatsBaseline.containsKey(qualityFamily(code)) &&
                        f.beatsBaseline.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tr('Marché récent : pas encore évalué par le moteur sur l’historique. Chiffres indicatifs.'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: BrandColors.orange),
                        ),
                      )
                    else if (weak.contains(qualityFamily(code)))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tr('Prudence : sur l’historique, le moteur ne fait pas mieux qu’une simple fréquence sur ce type de marché. Chiffres indicatifs.'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: BrandColors.orange),
                        ),
                      ),
                    for (final l
                        in lines.where((l) => l.key.startsWith('$code.')))
                      _MarketLine(
                          line: l,
                          label: outcomeKeyLabel(l.key, home, away),
                          highlight: l.key == highlightKey,
                          onTap:
                              onSimulate == null ? null : () => onSimulate!(l)),
                  ],
                ),
              ),
            ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            tr('Cote juste = 1 ÷ estimation du modèle. Cote du marché = cote médiane des bookmakers ; l’écart compare l’estimation du modèle à celle du marché (marge retirée). Un écart positif n’est pas une garantie.'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _MarketLine extends StatelessWidget {
  const _MarketLine(
      {required this.line,
      required this.label,
      this.highlight = false,
      this.onTap});

  final FicheOddsLine line;
  final String label;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = line.modelProbability!;
    final edge = line.edge ?? 0;
    Widget cell(String head, String value, {Color? color}) => Expanded(
          child: Column(
            children: [
              Text(head,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Text(value,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );
    final box = Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: highlight ? Border.all(color: scheme.primary) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis)),
              if (highlight)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.primary),
                  ),
                  child: Text(tr('Pronostic'),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.primary)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              cell(tr('Modèle'), pct(p), color: scheme.primary),
              cell(tr('Cote juste'), decimal(1 / p)),
              cell(tr('Cote'), decimal(line.oddMedian)),
              cell(tr('Écart'), edgePoints(edge),
                  color: edge > 0 ? scheme.primary : scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(frequencyLabel(p),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              if (onTap != null)
                Icon(Icons.calculate_outlined, size: 16, color: scheme.primary),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return Semantics(
      button: true,
      label: trf('Simuler une mise sur {0}', [label]),
      child: GestureDetector(onTap: onTap, child: box),
    );
  }
}

/// Fait vérifié avec son étiquette « source · date heure ».
class FactCard extends StatelessWidget {
  const FactCard({super.key, required this.fact});

  final VerifiedFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_outlined, color: scheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fact.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(fact.text, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  SourceChip(label: fact.sourceLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Bloc de texte titré (« LE SCÉNARIO », « CE QUI PEUT TOUT CHANGER »…).
class TextBlock extends StatelessWidget {
  const TextBlock(
      {super.key,
      required this.title,
      this.body,
      this.items = const [],
      this.color});

  final String title;
  final String? body;
  final List<String> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                  color: c, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 6),
          if (body != null && body!.isNotEmpty)
            Text(body!, style: theme.textTheme.bodyMedium),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: c)),
                  Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Résultat réel comparé à l'estimation d'avant-match.
class ActualResultNotice extends StatelessWidget {
  const ActualResultNotice(
      {super.key, required this.fiche, required this.match});

  final AnalysisFiche fiche;
  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final key = actualOneXTwoKey(match.homeGoals, match.awayGoals);
    if (key == null || fiche.p(key) == null) return const SizedBox.shrink();
    final label = outcomeKeyLabel(key, match.home.name, match.away.name);
    return NoticeCard(
      icon: Icons.sports_score,
      text: trf(
          'Résultat réel : {0}-{1} ({2}). Avant le match, le modèle donnait {3} à cette issue.',
          [match.homeGoals, match.awayGoals, label, pct(fiche.p(key)!)]),
    );
  }
}

/// Mentions de bas d'onglet : moteur, IA, heure de rédaction et des données.
class AnalysisFooter extends ConsumerWidget {
  const AnalysisFooter({super.key, required this.analysis});

  final MatchAnalysis analysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final f = analysis.fiche;
    final evaluation = ref.watch(latestEvaluationProvider).valueOrNull;
    final at = analysis.createdAt;
    final data = analysis.sourceUpdatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                trf(
                    'Analyse rédigée par l’IA à partir de données vérifiées, le {0} à {1}{2}.',
                    [
                      shortDate(at),
                      timeLabel(at),
                      data == null
                          ? ''
                          : trf(' (données du {0} à {1})',
                              [shortDate(data), timeLabel(data)])
                    ]),
                style: muted,
              ),
            ),
          ],
        ),
        if (ref
                .watch(myPermissionsProvider)
                .valueOrNull
                ?.contains('ai.providers') ??
            false)
          TechLine(analysisId: analysis.id),
        const SizedBox(height: 4),
        Text(
          trf('Calculée avec les seuls matchs joués avant le coup d’envoi ({0} matchs de la compétition). {1}',
              [f.competitionMatches, reliabilityExplanation(f)]),
          style: muted,
        ),
        if (evaluation != null && evaluation.oneXTwo.matches > 0) ...[
          const SizedBox(height: 4),
          Text(
            trf(
                'Qualité mesurée sur {0} matchs passés : issue la plus probable juste dans {1} des cas.',
                [
                  evaluation.oneXTwo.matches,
                  pct(evaluation.oneXTwo.accuracyModel)
                ]),
            style: muted,
          ),
        ],
      ],
    );
  }
}

/// Détails techniques d'une analyse, visibles du seul super administrateur.
class TechLine extends ConsumerWidget {
  const TechLine({super.key, required this.analysisId});

  final int analysisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(analysisTechProvider(analysisId)).valueOrNull;
    if (t == null) return const SizedBox.shrink();
    final parts = [
      if (t['provider'] != null) '${t['provider']}',
      if (t['model'] != null) '${t['model']}',
      if (t['engine_version'] != null) trf('moteur {0}', [t['engine_version']]),
      if (t['prompt_version'] != null)
        trf('prompt v{0}', [t['prompt_version']]),
      if (t['latency_ms'] != null)
        trf('{0} s', [
          ((t['latency_ms'] as num) / 1000)
              .toStringAsFixed(1)
              .replaceAll('.', decimalSeparator)
        ]),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return SuperAdminNote(text: parts.join(' · '));
  }
}

/// Avertissement présent en bas de chaque onglet.
class ResponsibleNote extends StatelessWidget {
  const ResponsibleNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(
        tr('Estimations à titre d’information, pas des certitudes. Aucun gain n’est garanti. Interdit aux moins de 18 ans ; pariez de façon responsable.'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
