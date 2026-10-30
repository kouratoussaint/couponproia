import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../assistant/data/assistant_models.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/lab_repository.dart';

/// Laboratoire IA : générateur manuel, puis analyse, optimisation, simulation et comparaison
/// de vos coupons. Tout est recalculé par le serveur ; les simulations sont signalées comme telles.
class LabScreen extends ConsumerStatefulWidget {
  const LabScreen({super.key, this.initialCouponId});

  final String? initialCouponId;

  @override
  ConsumerState<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends ConsumerState<LabScreen> {
  String? _couponId;
  bool _busy = false;
  Map<String, dynamic>? _diagnosis;
  List<Alternative>? _alternatives;
  CouponSimulation? _simulation;
  final Set<String> _compareIds = {};
  List<ComparisonRow>? _comparison;

  @override
  void initState() {
    super.initState();
    _couponId = widget.initialCouponId;
  }

  void _clearResults() {
    _diagnosis = null;
    _alternatives = null;
    _simulation = null;
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is LabException ? e.toString() : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveManual(List<ManualPick> picks) => _run(() async {
        final id = await ref
            .read(labRepositoryProvider)
            .build([for (final p in picks) (matchId: p.matchId, key: p.key)]);
        ref.read(manualCouponProvider.notifier).clear();
        ref.invalidate(savedCouponsProvider);
        if (!mounted) return;
        setState(() {
          _couponId = id;
          _clearResults();
        });
        showMessage(context, 'Coupon vérifié et enregistré dans Mes coupons.');
      });

  Future<void> _apply(UserCoupon coupon, Alternative a) => _run(() async {
        final selections = [
          for (final s in coupon.selections)
            if (s.position == a.replacePosition)
              (matchId: a.matchId, key: a.key)
            else
              (matchId: s.match.id, key: s.key),
        ];
        final id = await ref.read(labRepositoryProvider).build(selections);
        ref.invalidate(savedCouponsProvider);
        if (!mounted) return;
        setState(() {
          _couponId = id;
          _clearResults();
        });
        showMessage(context,
            'Nouvelle version enregistrée (l’originale est conservée).');
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flags =
        ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};
    if (flags['ai_lab'] == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Laboratoire IA')),
        body: const InfoMessage(
            icon: Icons.pause_circle_outline,
            title: 'Laboratoire momentanément indisponible'),
      );
    }
    final picks = ref.watch(manualCouponProvider);
    final saved = ref.watch(savedCouponsProvider);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Laboratoire IA')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SectionTitle('Générateur manuel'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (picks.isEmpty)
                    Text(
                      'Ouvrez un match (onglet Matchs) et touchez une cote pour l’ajouter. Une sélection par match.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else ...[
                    for (final p in picks)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.matchLabel),
                        subtitle: Text(p.label),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(decimal(p.odd),
                                style: theme.textTheme.titleSmall),
                            IconButton(
                              tooltip: 'Retirer',
                              icon: const Icon(Icons.close),
                              onPressed: () => ref
                                  .read(manualCouponProvider.notifier)
                                  .remove(p.matchId),
                            ),
                          ],
                        ),
                      ),
                    const Divider(),
                    Text('Cote indicative : ${decimal(indicativeOdd(picks))}',
                        style: theme.textTheme.titleMedium),
                    Text(
                        'Le serveur relit les cotes, vérifie chaque match et recalcule tout à l’enregistrement.',
                        style: muted),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                            onPressed: () =>
                                ref.read(manualCouponProvider.notifier).clear(),
                            child: const Text('Vider')),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _saveManual(picks),
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Vérifier et enregistrer'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SectionTitle('Analyser un de mes coupons'),
          saved.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(userMessageFor(e)),
            data: (list) {
              if (list.isEmpty) {
                return Text(
                    'Enregistrez d’abord un coupon (assistant ou générateur manuel).',
                    style: theme.textTheme.bodyMedium);
              }
              final current = list.where((c) => c.id == _couponId).firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(current?.id),
                    initialValue: current?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Coupon',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: [
                      for (final c in list)
                        DropdownMenuItem(
                            value: c.id,
                            child:
                                Text(c.title, overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (v) => setState(() {
                      _couponId = v;
                      _clearResults();
                    }),
                  ),
                  if (current != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final d = await ref
                                        .read(labRepositoryProvider)
                                        .analyze(current.id);
                                    if (mounted) setState(() => _diagnosis = d);
                                  }),
                          icon: const Icon(Icons.manage_search),
                          label: const Text('Analyser'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final a = await ref
                                        .read(labRepositoryProvider)
                                        .optimize(current.id);
                                    if (mounted) {
                                      setState(() => _alternatives = a);
                                    }
                                  }),
                          icon: const Icon(Icons.tune),
                          label: const Text('Optimiser'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final s = await ref
                                        .read(labRepositoryProvider)
                                        .simulate(current.id);
                                    if (mounted) {
                                      setState(() => _simulation = s);
                                    }
                                  }),
                          icon: const Icon(Icons.casino_outlined),
                          label: const Text('Simuler'),
                        ),
                        TextButton(
                            onPressed: () =>
                                context.push(AppRoutes.myCouponFor(current.id)),
                            child: const Text('Détail')),
                      ],
                    ),
                    if (_diagnosis != null)
                      _DiagnosisView(diagnosis: _diagnosis!),
                    if (_alternatives != null)
                      _AlternativesView(
                          alternatives: _alternatives!,
                          onApply: (a) => _apply(current, a),
                          busy: _busy),
                    if (_simulation != null)
                      _SimulationView(simulation: _simulation!),
                  ],
                ],
              );
            },
          ),
          const SectionTitle('Comparer des coupons'),
          saved.maybeWhen(
            data: (list) => list.length < 2
                ? Text('Il faut au moins deux coupons enregistrés.',
                    style: theme.textTheme.bodyMedium)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in list.take(12))
                        CheckboxListTile(
                          dense: true,
                          value: _compareIds.contains(c.id),
                          title: Text(c.title, overflow: TextOverflow.ellipsis),
                          onChanged: (v) => setState(() {
                            if (v == true && _compareIds.length < 3) {
                              _compareIds.add(c.id);
                            } else {
                              _compareIds.remove(c.id);
                            }
                            _comparison = null;
                          }),
                        ),
                      FilledButton.tonal(
                        onPressed: _busy || _compareIds.length < 2
                            ? null
                            : () => _run(() async {
                                  final r = await ref
                                      .read(labRepositoryProvider)
                                      .compare(_compareIds.toList());
                                  if (mounted) setState(() => _comparison = r);
                                }),
                        child: Text('Comparer (${_compareIds.length}/3)'),
                      ),
                      if (_comparison != null)
                        _ComparisonView(rows: _comparison!),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisView extends StatelessWidget {
  const _DiagnosisView({required this.diagnosis});

  final Map<String, dynamic> diagnosis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<String> list(String k) => (diagnosis[k] as List? ?? const [])
        .map((e) => e is Map ? '${e['selection']} : ${e['raison']}' : '$e')
        .toList();
    Widget section(String title, List<String> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                for (final i in items)
                  Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('• $i', style: theme.textTheme.bodySmall)),
              ],
            ),
          );
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cote ${decimal((diagnosis['total_odd'] as num).toDouble())} · probabilité estimée '
              '${pct((diagnosis['combined_probability'] as num).toDouble())}'
              '${diagnosis['implied_probability'] == null ? '' : ' (marché ${pct((diagnosis['implied_probability'] as num).toDouble())})'}',
              style: theme.textTheme.titleSmall,
            ),
            section('Sélections les plus fragiles', list('fragiles')),
            section('À vérifier', list('alertes')),
            section('Qualité des données', list('qualite')),
          ],
        ),
      ),
    );
  }
}

class _AlternativesView extends StatelessWidget {
  const _AlternativesView(
      {required this.alternatives, required this.onApply, required this.busy});

  final List<Alternative> alternatives;
  final void Function(Alternative) onApply;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (alternatives.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
            'Aucune alternative plus probable selon le modèle pour les sélections les plus fragiles.'),
      );
    }
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Text('Alternatives plus probables selon le modèle',
                style: theme.textTheme.labelLarge),
          ),
          for (final a in alternatives)
            ListTile(
              title: Text('${a.selection} (${a.match})'),
              subtitle: Text(
                'Remplace n° ${a.replacePosition} : ${a.replaced}\n'
                'Cote ${decimal(a.odd)} · modèle ${pct(a.modelProbability)} → coupon ${decimal(a.newTotalOdd)}, '
                'probabilité ${pct(a.newCombinedProbability)}${a.sameMatch ? ' · même match' : ''}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Créer cette version',
                onPressed: busy ? null : () => onApply(a),
                icon: const Icon(Icons.call_split),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
                'Appliquer crée une nouvelle version vérifiée par le serveur ; l’originale est conservée.',
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _SimulationView extends StatelessWidget {
  const _SimulationView({required this.simulation});

  final CouponSimulation simulation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = simulation;
    final n = s.distribution.length - 1;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.casino_outlined, size: 18),
                const SizedBox(width: 6),
                Text('SIMULATION',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(letterSpacing: 1.2)),
              ],
            ),
            const SizedBox(height: 6),
            Text(s.label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Text(
                'Probabilité que toutes les sélections passent (modèle) : ${pct(s.probabilityAllCorrect)}',
                style: theme.textTheme.titleSmall),
            Text(
                'Sur ${s.runs} coupons simulés : ${s.simulatedWins} gagnants (fourchette attendue ${s.winsLow} à ${s.winsHigh}).'),
            Text(
                'Sélections justes en moyenne : ${decimal(s.expectedCorrect)} sur $n.'),
            const SizedBox(height: 8),
            for (var k = n; k >= 0; k--)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    SizedBox(
                        width: 110,
                        child: Text('$k juste${k > 1 ? 's' : ''} sur $n',
                            style: theme.textTheme.bodySmall)),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: s.distribution[k].clamp(0.0, 1.0).toDouble(),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(
                        width: 44,
                        child: Text(pct(s.distribution[k]),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Selon le modèle, pour 1 misé sur ce coupon, retour moyen estimé : ${decimal(s.modelReturnPerUnit)} '
              '(en dessous de 1, le coupon perd en moyenne). Estimation, pas une promesse.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonView extends StatelessWidget {
  const _ComparisonView({required this.rows});

  final List<ComparisonRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    DataRow row(String label, String Function(ComparisonRow) value) =>
        DataRow(cells: [
          DataCell(Text(label, style: head)),
          for (final r in rows) DataCell(Text(value(r)))
        ]);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          columns: [
            const DataColumn(label: Text('')),
            for (var i = 0; i < rows.length; i++)
              DataColumn(label: Text('Coupon ${i + 1}')),
          ],
          rows: [
            row('Sélections', (r) => '${r.selections}'),
            row('Cote totale', (r) => decimal(r.totalOdd)),
            row('Probabilité (modèle)', (r) => pct(r.combinedProbability)),
            row(
                'Probabilité (marché)',
                (r) => r.impliedProbability == null
                    ? '—'
                    : pct(r.impliedProbability!)),
            row('Compétitions', (r) => '${r.competitions}'),
            row('Paires liées', (r) => '${r.correlatedPairs}'),
            row('Fiabilité faible', (r) => '${r.lowReliability}'),
            row('Marchés non validés', (r) => '${r.unvalidatedMarkets}'),
            row('Plus fragile', (r) => r.weakest ?? '—'),
          ],
        ),
      ),
    );
  }
}
