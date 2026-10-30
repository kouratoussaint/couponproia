import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/providers.dart';
import '../analysis/data/analysis_format.dart';
import '../coupons/data/coupon_models.dart';
import '../matches/presentation/sports_widgets.dart';

final platformPerformanceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int?>((ref, days) async {
  final res = await ref
      .watch(supabaseClientProvider)
      .rpc('platform_performance', params: {'p_days': days});
  return Map<String, dynamic>.from(res as Map);
});

final myPerformanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.watch(supabaseClientProvider).rpc('my_performance');
  return Map<String, dynamic>.from(res as Map);
});

double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
List<Map<String, dynamic>> _rows(Object? v) => [
      for (final x in (v as List? ?? const []))
        Map<String, dynamic>.from(x as Map)
    ];

const _marketNames = {
  '1X2': 'Résultat (1X2)',
  'DC': 'Double chance',
  'OU': 'Plus / moins',
  'BTTS': 'Les deux marquent'
};

/// Performances : coupons de la plateforme (publiés avant le coup d'envoi, réglés sur le score
/// à 90 minutes) et vos coupons enregistrés. Aucun pari réel n'est compté.
class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Performances'),
          bottom: const TabBar(
              tabs: [Tab(text: 'Plateforme'), Tab(text: 'Mes coupons')]),
        ),
        body: const TabBarView(children: [_PlatformTab(), _MineTab()]),
      ),
    );
  }
}

class _PlatformTab extends ConsumerStatefulWidget {
  const _PlatformTab();

  @override
  ConsumerState<_PlatformTab> createState() => _PlatformTabState();
}

class _PlatformTabState extends ConsumerState<_PlatformTab> {
  int? _days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perf = ref.watch(platformPerformanceProvider(_days));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(platformPerformanceProvider(_days)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (label, days) in [
                ('Tout', null),
                ('30 jours', 30),
                ('7 jours', 7)
              ])
                ChoiceChip(
                    label: Text(label),
                    selected: _days == days,
                    onSelected: (_) => setState(() => _days = days)),
            ],
          ),
          perf.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(24), child: LinearProgressIndicator()),
            error: (e, _) => InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Indisponible',
                body: userMessageFor(e)),
            data: (p) {
              final settled = _i(p['won']) + _i(p['lost']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(p['scope'] as String? ?? '',
                      style: theme.textTheme.bodySmall),
                  _Totals(p: p),
                  if (settled == 0)
                    const InfoMessage(
                      icon: Icons.hourglass_empty,
                      title: 'Pas encore de coupon réglé',
                      body:
                          'Les statistiques apparaîtront après les premiers matchs des coupons publiés.',
                    )
                  else ...[
                    Card(
                      child: ListTile(
                        title: Text(
                            'Rendement théorique : ${_signedPct(_dn(p['theoretical_return']))}'),
                        subtitle: Text(
                            '${p['stake_note']}. Calcul : (somme des cotes des coupons gagnants − nombre de coupons réglés) / nombre de coupons réglés.'),
                      ),
                    ),
                    _Table(
                      title: 'Par catégorie',
                      rows: _rows(p['by_category']),
                      label: (r) => categoryLabels[r['key']] ?? '${r['key']}',
                      value: (r) =>
                          '${_i(r['won'])}/${_i(r['won']) + _i(r['lost'])} gagnés · ${_rate(r['win_rate'])} · cote moy. ${_odd(r['average_odd'])}',
                    ),
                    _Table(
                      title: 'Par compétition (sélections)',
                      rows: _rows(p['by_competition']),
                      label: (r) => '${r['key']}',
                      value: (r) =>
                          '${_i(r['won'])}/${_i(r['won']) + _i(r['lost'])} justes · ${_rate(r['hit_rate'])}',
                    ),
                    _Table(
                      title: 'Par marché (sélections)',
                      rows: _rows(p['by_market']),
                      label: (r) => _marketNames[r['key']] ?? '${r['key']}',
                      value: (r) =>
                          '${_i(r['won'])}/${_i(r['won']) + _i(r['lost'])} justes · ${_rate(r['hit_rate'])} (modèle moy. ${_rate(r['average_model_probability'])})',
                    ),
                    _WeeklyChart(rows: _rows(p['by_week'])),
                    _Table(
                      title: 'Calibration réelle (annoncé → constaté)',
                      rows: _rows(p['calibration']),
                      label: (r) => 'Annoncé ${_rate(r['predicted'])}',
                      value: (r) =>
                          'constaté ${_rate(r['observed'])} sur ${_i(r['selections'])} sélections',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Coupons réglés automatiquement sur le score à 90 minutes ; reports et annulations comptent pour 1,00. '
                    'Les coupons retirés ne sont pas comptés. Les performances passées ne garantissent pas les performances futures ; '
                    'aucun gain n’est garanti. Coupon Pro IA n’est pas un bookmaker : aucun pari réel n’est enregistré ici.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MineTab extends ConsumerWidget {
  const _MineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perf = ref.watch(myPerformanceProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myPerformanceProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          perf.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Indisponible',
                body: userMessageFor(e)),
            data: (p) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p['scope'] as String? ?? '',
                    style: Theme.of(context).textTheme.bodySmall),
                _Totals(p: p),
                if (_i(p['coupons']) == 0)
                  const InfoMessage(
                    icon: Icons.bookmarks_outlined,
                    title: 'Aucun coupon enregistré',
                    body:
                        'Enregistrez des coupons depuis l’assistant ou le Laboratoire pour suivre leurs résultats.',
                  )
                else ...[
                  _Table(
                    title: 'Par marché (sélections)',
                    rows: _rows(p['by_market']),
                    label: (r) => _marketNames[r['key']] ?? '${r['key']}',
                    value: (r) =>
                        '${_i(r['won'])}/${_i(r['won']) + _i(r['lost'])} justes',
                  ),
                  _WeeklyChart(rows: _rows(p['by_week'])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _rate(Object? v) => v == null ? '—' : pct((v as num).toDouble());
String _odd(Object? v) => v == null ? '—' : decimal((v as num).toDouble());
String _signedPct(double? v) {
  if (v == null) return '—';
  final p = (v * 100).round();
  return '${p > 0 ? '+' : p < 0 ? '−' : ''}${p.abs()} %';
}

class _Totals extends StatelessWidget {
  const _Totals({required this.p});

  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String label, String value, [Color? color]) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: theme.textTheme.titleLarge?.copyWith(color: color)),
              Text(label,
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                tile('Coupons', '${_i(p['coupons'])}'),
                tile('Gagnés', '${_i(p['won'])}', theme.colorScheme.primary),
                tile('Perdus', '${_i(p['lost'])}', theme.colorScheme.error),
                tile('Annulés', '${_i(p['void'])}'),
                tile('En cours', '${_i(p['pending'])}'),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                tile('Taux de réussite', _rate(p['win_rate'])),
                tile('Cote moyenne', _odd(p['average_odd'])),
                if (p.containsKey('withdrawn'))
                  tile('Retirés (non comptés)', '${_i(p['withdrawn'])}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table(
      {required this.title,
      required this.rows,
      required this.label,
      required this.value});

  final String title;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) label;
  final String Function(Map<String, dynamic>) value;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        Card(
          child: Column(
            children: [
              for (final r in rows)
                ListTile(
                    dense: true,
                    title: Text(label(r)),
                    subtitle: Text(value(r)))
            ],
          ),
        ),
      ],
    );
  }
}

/// Évolution hebdomadaire : barres gagnés / perdus par semaine.
class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final recent = rows.length > 10 ? rows.sublist(rows.length - 10) : rows;
    final max =
        recent.map((r) => _i(r['coupons'])).fold(1, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Évolution par semaine'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Column(
              children: [
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final r in recent)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                    height: 100 * _i(r['lost']) / max,
                                    color: theme.colorScheme.error
                                        .withValues(alpha: 0.75)),
                                Container(
                                    height: 100 * _i(r['won']) / max,
                                    color: theme.colorScheme.primary),
                                Container(
                                  height: 100 *
                                      (_i(r['coupons']) -
                                          _i(r['won']) -
                                          _i(r['lost'])) /
                                      max,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final r in recent)
                      Expanded(
                        child: Text(
                            '${r['week']}'.substring(5).replaceAll('-', '/'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    'Vert : gagnés · rouge : perdus · gris : annulés ou en cours (semaine de publication)',
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
