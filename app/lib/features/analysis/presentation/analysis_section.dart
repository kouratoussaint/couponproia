import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/data/sports_models.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/analysis_format.dart';
import '../data/analysis_models.dart';
import '../data/analysis_repository.dart';

/// Bloc « Analyse IA » de la fiche d'un match : bouton, puis fiche statistique du
/// moteur et texte de l'IA vérifié. Une analyse existante s'affiche dès l'ouverture.
class AnalysisSection extends ConsumerStatefulWidget {
  const AnalysisSection({super.key, required this.match});

  final MatchSummary match;

  @override
  ConsumerState<AnalysisSection> createState() => _AnalysisSectionState();
}

class _AnalysisSectionState extends ConsumerState<AnalysisSection> {
  MatchAnalysis? _fresh;
  bool _running = false;

  MatchSummary get match => widget.match;

  bool get _analyzable => !{
        MatchStatus.postponed,
        MatchStatus.cancelled,
        MatchStatus.abandoned
      }.contains(match.status);

  Future<void> _run({bool force = false}) async {
    setState(() => _running = true);
    try {
      final result = await ref
          .read(analysisRepositoryProvider)
          .analyze(match.id, force: force);
      if (mounted) setState(() => _fresh = result);
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
    final flags = ref.watch(featureFlagsProvider).valueOrNull ?? const {};
    if (flags['match_analysis'] == false) return const SizedBox.shrink();
    final stored = ref.watch(storedAnalysisProvider(match.id));
    final analysis = _fresh ?? stored.valueOrNull;
    final isAdmin =
        (ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{})
            .contains('ai.configure');

    final played = match.status == MatchStatus.finished ||
        match.status == MatchStatus.awarded;
    final canRefresh = analysis == null || analysis.status != 'ok' || !played;

    Widget button() {
      if (!_analyzable) {
        return const FilledButton.tonal(
            onPressed: null,
            child: Text('Analyse indisponible (match reporté ou annulé)'));
      }
      if (_running) {
        return const FilledButton.tonal(
          onPressed: null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Analyse en cours…'),
            ],
          ),
        );
      }
      if (analysis == null) {
        return FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Analyser avec l’IA'),
        );
      }
      return Row(
        children: [
          if (canRefresh)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.refresh),
                label: const Text('Mettre à jour l’analyse'),
              ),
            ),
          if (isAdmin) ...[
            if (canRefresh) const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Régénérer (administrateur)',
              onPressed: () => _run(force: true),
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stored.isLoading && _fresh == null)
          const LinearProgressIndicator()
        else
          button(),
        if (analysis != null) AnalysisView(analysis: analysis, match: match),
      ],
    );
  }
}

/// Affichage complet d'une analyse (sans bouton), réutilisable.
class AnalysisView extends ConsumerWidget {
  const AnalysisView({super.key, required this.analysis, required this.match});

  final MatchAnalysis analysis;
  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final f = analysis.fiche;
    final ai = analysis.ai;
    final home = match.home.name;
    final away = match.away.name;
    final played = match.hasScore &&
        (match.status == MatchStatus.finished ||
            match.status == MatchStatus.awarded);
    final evaluation = ref.watch(latestEvaluationProvider).valueOrNull;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final missing = mergedMissing(f, ai);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          played ? 'Analyse d’avant-match' : 'Analyse IA',
          trailing: ReliabilityChip(reliability: f.reliability),
        ),
        if (ai != null && ai.summary.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ai.summary, style: theme.textTheme.bodyLarge),
            ),
          )
        else
          _Notice(
              icon: Icons.info_outline,
              text: statsOnlyReason(analysis.statusReason)),
        if (played) _ActualResult(fiche: f, match: match),
        ProbabilitiesCard(fiche: f, home: home, away: away),
        if (f.comparableLines.isNotEmpty)
          _MarketCard(fiche: f, home: home, away: away),
        if (ai != null) ...[
          if (ai.form.isNotEmpty)
            _TextCard(
                title: 'Forme',
                body: ai.form,
                form: (f.homeForm, f.awayForm, home, away)),
          if (ai.homeFactors.isNotEmpty)
            _ListCard(
                title: 'Atouts de $home',
                items: ai.homeFactors,
                icon: Icons.home_outlined),
          if (ai.awayFactors.isNotEmpty)
            _ListCard(
                title: 'Atouts de $away',
                items: ai.awayFactors,
                icon: Icons.flight_takeoff),
          if (ai.trends.isNotEmpty)
            _ListCard(
                title: 'Tendances', items: ai.trends, icon: Icons.trending_up),
          if (ai.picks.isNotEmpty)
            _PicksCard(picks: ai.picks, home: home, away: away),
          if (ai.risks.isNotEmpty)
            _ListCard(
                title: 'Risques',
                items: ai.risks,
                icon: Icons.warning_amber_outlined),
        ] else if (f.homeForm.isNotEmpty || f.awayForm.isNotEmpty)
          _TextCard(
              title: 'Forme',
              body: null,
              form: (f.homeForm, f.awayForm, home, away)),
        if (missing.isNotEmpty)
          _ListCard(
              title: 'Informations manquantes',
              items: missing,
              icon: Icons.help_outline),
        if (ai != null && ai.conclusion.isNotEmpty)
          _TextCard(title: 'Conclusion', body: ai.conclusion),
        if (ai != null && !ai.recommendationPossible)
          const _Notice(
            icon: Icons.do_not_disturb_on_outlined,
            text:
                'Pas de recommandation pour ce match : données insuffisantes ou estimation trop fragile.',
          ),
        const SizedBox(height: 8),
        Text(
          [
            'Moteur ${analysis.engineVersion}',
            if (analysis.provider != null)
              'IA ${analysis.provider} (${analysis.model})',
            'analyse du ${shortDate(analysis.createdAt)}/${analysis.createdAt.year} à ${timeLabel(analysis.createdAt)}',
          ].join(' · '),
          style: muted,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Calculée avec les seuls matchs joués avant le coup d’envoi (${f.competitionMatches} matchs de la compétition). '
          '${reliabilityExplanation(f)} Ce sont des estimations, pas des certitudes.',
          style: muted,
          textAlign: TextAlign.center,
        ),
        if (evaluation != null && evaluation.oneXTwo.matches > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Qualité mesurée sur ${evaluation.oneXTwo.matches} matchs passés'
            '${evaluation.season == null ? '' : ' (${seasonLabel(evaluation.season!)})'} : '
            'issue la plus probable juste dans ${pct(evaluation.oneXTwo.accuracyModel)} des cas.',
            style: muted,
            textAlign: TextAlign.center,
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
      Reliability.moyenne => scheme.tertiary,
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

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

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

/// Barre de probabilité avec libellé et pourcentage.
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
        ],
      ),
    );
  }
}

class ProbabilitiesCard extends StatelessWidget {
  const ProbabilitiesCard(
      {super.key, required this.fiche, required this.home, required this.away});

  final AnalysisFiche fiche;
  final String home;
  final String away;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fiche;
    const oneXTwo = ['1X2.HOME', '1X2.DRAW', '1X2.AWAY'];
    final best = oneXTwo.where((k) => f.p(k) != null).fold<String?>(
          null,
          (b, k) => b == null || f.p(k)! > f.p(b)! ? k : b,
        );
    const others = [
      'DC.1X',
      'DC.X2',
      'OU.OVER.1.5',
      'OU.OVER.2.5',
      'OU.UNDER.2.5',
      'BTTS.YES'
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Probabilités du modèle', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final k in oneXTwo)
              if (f.p(k) != null)
                ProbabilityBar(
                    label: outcomeKeyLabel(k, home, away),
                    probability: f.p(k)!,
                    highlight: k == best),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in others)
                  if (f.p(k) != null)
                    _Pill(
                        label: outcomeKeyLabel(k, home, away),
                        value: pct(f.p(k)!)),
              ],
            ),
            if (f.weakGroups.any((g) => g == 'OU' || g == 'BTTS')) ...[
              const SizedBox(height: 8),
              Text(
                'Prudence : sur l’historique, le moteur ne fait pas mieux qu’une simple fréquence pour '
                '${[
                  if (f.weakGroups.contains('OU')) 'le nombre de buts',
                  if (f.weakGroups.contains('BTTS')) '« les deux marquent »'
                ].join(' et ')}. '
                'Ces chiffres sont indicatifs.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Buts attendus : $home ${decimal(f.expectedGoalsHome)} – ${decimal(f.expectedGoalsAway)} $away',
              style: theme.textTheme.bodyMedium,
            ),
            if (f.topScores.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Scores les plus probables : ${f.topScores.map((s) => '${s.score} (${pct(s.probability)})').join(' · ')}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label  ', style: theme.textTheme.labelMedium),
          TextSpan(
              text: value,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
        ]),
      ),
    );
  }
}

class _MarketCard extends StatelessWidget {
  const _MarketCard(
      {required this.fiche, required this.home, required this.away});

  final AnalysisFiche fiche;
  final String home;
  final String away;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = fiche.comparableLines;
    final head = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Modèle et marché', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Issue', style: head)),
                SizedBox(
                    width: 48,
                    child: Text('Cote', style: head, textAlign: TextAlign.end)),
                SizedBox(
                    width: 56,
                    child:
                        Text('Marché', style: head, textAlign: TextAlign.end)),
                SizedBox(
                    width: 56,
                    child:
                        Text('Modèle', style: head, textAlign: TextAlign.end)),
                SizedBox(
                    width: 60,
                    child:
                        Text('Écart', style: head, textAlign: TextAlign.end)),
              ],
            ),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(outcomeKeyLabel(l.key, home, away),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis),
                    ),
                    SizedBox(
                        width: 48,
                        child: Text(decimal(l.oddMedian),
                            textAlign: TextAlign.end)),
                    SizedBox(
                        width: 56,
                        child: Text(pct(l.impliedProbability!),
                            textAlign: TextAlign.end)),
                    SizedBox(
                        width: 56,
                        child: Text(pct(l.modelProbability!),
                            textAlign: TextAlign.end)),
                    SizedBox(
                      width: 60,
                      child: Text(
                        edgePoints(l.edge ?? 0),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: (l.edge ?? 0) > 0
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Marché : probabilité implicite de la cote médiane, marge des bookmakers retirée. '
              'Un écart positif signifie que le modèle estime l’issue plus probable que le marché ; '
              'ce n’est pas une garantie.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.title, required this.body, this.form});

  final String title;
  final String? body;
  final (String, String, String, String)? form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = this.form;
    Widget formRow(String name, String letters) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
              FormChips(results: letters.split('')),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, style: theme.textTheme.bodyMedium),
            ],
            if (form != null) ...[
              if (form.$1.isNotEmpty) formRow(form.$3, form.$1),
              if (form.$2.isNotEmpty) formRow(form.$4, form.$2),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard(
      {required this.title, required this.items, required this.icon});

  final String title;
  final List<String> items;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                        child: Text(item, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PicksCard extends StatelessWidget {
  const _PicksCard(
      {required this.picks, required this.home, required this.away});

  final List<MarketPick> picks;
  final String home;
  final String away;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Marchés envisageables', style: theme.textTheme.labelLarge),
            for (final p in picks)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(outcomeKeyLabel(p.key, home, away),
                                style: theme.textTheme.titleSmall)),
                        Text(pct(p.modelProbability),
                            style: theme.textTheme.titleSmall
                                ?.copyWith(color: theme.colorScheme.primary)),
                      ],
                    ),
                    if (p.oddMedian != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Cote médiane ${decimal(p.oddMedian!)}'
                          '${p.edge == null ? '' : ' · écart modèle/marché ${edgePoints(p.edge!)}'}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(p.justification, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActualResult extends StatelessWidget {
  const _ActualResult({required this.fiche, required this.match});

  final AnalysisFiche fiche;
  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final key = actualOneXTwoKey(match.homeGoals, match.awayGoals);
    if (key == null || fiche.p(key) == null) return const SizedBox.shrink();
    final label = outcomeKeyLabel(key, match.home.name, match.away.name);
    return _Notice(
      icon: Icons.sports_score,
      text: 'Résultat réel : ${match.homeGoals}-${match.awayGoals} ($label). '
          'Avant le match, le modèle donnait ${pct(fiche.p(key)!)} à cette issue.',
    );
  }
}
