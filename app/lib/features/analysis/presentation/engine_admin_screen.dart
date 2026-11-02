import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/analysis_format.dart';
import '../data/analysis_models.dart';
import '../data/analysis_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Administration du moteur d'analyse : qualité mesurée sur l'historique et
/// consommation de l'IA. Réservé à la permission ai.configure.
class EngineAdminScreen extends ConsumerStatefulWidget {
  const EngineAdminScreen({super.key});

  @override
  ConsumerState<EngineAdminScreen> createState() => _EngineAdminScreenState();
}

class _EngineAdminScreenState extends ConsumerState<EngineAdminScreen> {
  bool _running = false;

  Future<void> _evaluate() async {
    setState(() => _running = true);
    try {
      await ref.read(analysisRepositoryProvider).evaluateEngine();
      ref.invalidate(latestEvaluationProvider);
      if (mounted) showMessage(context, tr('Évaluation terminée.'));
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
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!permissions.contains('ai.configure')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Moteur et IA'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Accès réservé aux administrateurs')),
      );
    }
    final evaluation = ref.watch(latestEvaluationProvider);
    final requests = ref.watch(recentAiRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Moteur et IA')),
        actions: [
          IconButton(
            tooltip: tr('Actualiser'),
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(latestEvaluationProvider);
              ref.invalidate(recentAiRequestsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          FilledButton.icon(
            onPressed: _running ? null : _evaluate,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fact_check_outlined),
            label: Text(_running
                ? tr('Évaluation en cours…')
                : tr('Évaluer le moteur sur l’historique')),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Chaque match terminé est prédit avec les seuls matchs joués avant lui, puis comparé au résultat réel.'),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          evaluation.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(24), child: LinearProgressIndicator()),
            error: (e, _) => InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: tr('Indisponible'),
                body: userMessageFor(e)),
            data: (e) => e == null
                ? InfoMessage(
                    icon: Icons.query_stats,
                    title: tr('Aucune évaluation pour l’instant'))
                : _EvaluationView(evaluation: e),
          ),
          SectionTitle(tr('Requêtes IA (7 derniers jours)')),
          requests.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(userMessageFor(e)),
            data: (rows) => _AiUsage(rows: rows),
          ),
        ],
      ),
    );
  }
}

class _EvaluationView extends StatelessWidget {
  const _EvaluationView({required this.evaluation});

  final EngineEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = evaluation;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(trf('Dernière évaluation · {0}', [e.engineVersion])),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  trf('{0} matchs évalués{1} · le {2}/{3} à {4}', [
                    e.oneXTwo.matches,
                    e.season == null
                        ? ''
                        : trf(' · saison {0}', [seasonLabel(e.season!)]),
                    shortDate(e.createdAt),
                    e.createdAt.year,
                    timeLabel(e.createdAt)
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _MetricsTable(rows: [
                  (tr('Résultat 1 / N / 2'), e.oneXTwo),
                  if (e.over25 != null) (tr('Plus de 2,5 buts'), e.over25!),
                  if (e.btts != null) (tr('Les deux marquent'), e.btts!),
                  if (e.dnb != null) (tr('Remboursé si nul'), e.dnb!),
                  if (e.teamTotals != null)
                    (tr('Buts par équipe'), e.teamTotals!),
                ]),
                const SizedBox(height: 12),
                Text(
                  tr('Brier et log-loss : plus c’est bas, mieux c’est. Référence = fréquences observées jusque-là dans la compétition (ex. part des victoires à domicile). Le modèle n’apporte de la valeur que s’il fait mieux que cette référence.'),
                  style: muted,
                ),
              ],
            ),
          ),
        ),
        if (e.calibration.isNotEmpty) ...[
          SectionTitle(tr('Calibration (1 / N / 2)')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in e.calibration)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(trf('Annoncé {0}–{1}',
                                  [pct(b.from), pct(b.to)]))),
                          Text(trf('réalisé {0}', [pct(b.observed)]),
                              style: theme.textTheme.titleSmall),
                          SizedBox(
                              width: 72,
                              child: Text('(${b.count})',
                                  textAlign: TextAlign.end, style: muted)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                      tr('Un modèle bien calibré réalise à peu près ce qu’il annonce.'),
                      style: muted),
                ],
              ),
            ),
          ),
        ],
        if (e.perCompetition.isNotEmpty) ...[
          SectionTitle(tr('Par compétition (1 / N / 2)')),
          Card(
            child: Column(
              children: [
                for (final entry in e.perCompetition.entries)
                  ListTile(
                    dense: true,
                    title: Text(entry.key),
                    subtitle: Text(
                      trf('{0} matchs · Brier {1} (réf. {2}) · juste {3}', [
                        entry.value.matches,
                        decimal(entry.value.brierModel, 3),
                        decimal(entry.value.brierBaseline, 3),
                        pct(entry.value.accuracyModel)
                      ]),
                    ),
                    trailing: Icon(
                      entry.value.beatsBaseline
                          ? Icons.check_circle_outline
                          : Icons.remove_circle_outline,
                      color: entry.value.beatsBaseline
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricsTable extends StatelessWidget {
  const _MetricsTable({required this.rows});

  final List<(String, Metrics)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget cell(String text, {TextStyle? style}) => SizedBox(
        width: 78, child: Text(text, textAlign: TextAlign.end, style: style));
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(tr('Marché'), style: head)),
            cell(tr('Brier'), style: head),
            cell(tr('Log-loss'), style: head),
            cell(tr('Juste'), style: head),
          ],
        ),
        for (final (label, m) in rows) ...[
          const Divider(height: 14),
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              cell(decimal(m.brierModel, 3),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: m.beatsBaseline
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  )),
              cell(decimal(m.loglossModel, 3)),
              cell(pct(m.accuracyModel)),
            ],
          ),
          Row(
            children: [
              Expanded(child: Text(tr('  référence'), style: head)),
              cell(decimal(m.brierBaseline, 3), style: head),
              cell(decimal(m.loglossBaseline, 3), style: head),
              cell(m.accuracyBaseline == null ? '—' : pct(m.accuracyBaseline!),
                  style: head),
            ],
          ),
        ],
      ],
    );
  }
}

class _AiUsage extends StatelessWidget {
  const _AiUsage({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return InfoMessage(
          icon: Icons.history, title: tr('Aucune requête IA sur la période'));
    }
    final byStatus = <String, int>{};
    var cost = 0.0;
    var costKnown = false;
    for (final r in rows) {
      byStatus.update(r['status'] as String, (n) => n + 1, ifAbsent: () => 1);
      final c = r['cost_usd'];
      if (c != null) {
        cost += (c as num).toDouble();
        costKnown = true;
      }
    }
    final labels = {
      'success': tr('réussies'),
      'invalid': tr('refusées par les contrôles'),
      'error': tr('erreurs du fournisseur'),
      'stats_only': tr('fiche seule (sans IA)'),
      'rate_limited': tr('limitées'),
    };
    final lastErrors = rows.where((r) => r['error'] != null).take(3).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in byStatus.entries)
              Text('${e.value} ${labels[e.key] ?? e.key}'),
            const SizedBox(height: 8),
            Text(
              costKnown
                  ? trf('Coût estimé : {0} USD', [
                      cost.toStringAsFixed(4).replaceAll('.', decimalSeparator)
                    ])
                  : tr('Coût : non estimé'),
              style: theme.textTheme.titleSmall,
            ),
            if (lastErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(tr('Derniers messages'), style: theme.textTheme.labelLarge),
              for (final r in lastErrors)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${r['provider'] ?? '—'} : ${r['error']}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
