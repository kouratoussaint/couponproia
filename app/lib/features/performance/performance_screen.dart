import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/providers.dart';
import '../analysis/data/analysis_format.dart';
import '../coupons/data/coupon_models.dart';
import '../matches/presentation/sports_widgets.dart';
import '../simulator/data/stake_math.dart';
import '../simulator/presentation/stake_simulator_sheet.dart';
import '../system/system_providers.dart';

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
                ('90 jours', 90),
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
                    FixedStakeCard(p: p),
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
                    CalibrationChart(rows: _rows(p['calibration'])),
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

/// Résultat à mise fixe : ce qu'aurait donné la même mise sur chaque coupon réglé, au total et par
/// catégorie. Calcul théorique sur les cotes publiées ; aucun pari réel.
class FixedStakeCard extends ConsumerStatefulWidget {
  const FixedStakeCard({super.key, required this.p});

  final Map<String, dynamic> p;

  @override
  ConsumerState<FixedStakeCard> createState() => _FixedStakeCardState();
}

class _FixedStakeCardState extends ConsumerState<FixedStakeCard> {
  int _stake = 1000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cur = currencyLabel(ref.watch(publicSettingsProvider).valueOrNull);
    final p = widget.p;
    final settled = _i(p['settled']);
    final returned = _dn(p['returned']) ?? 0;
    final staked = settled * _stake;
    final back = (returned * _stake).round();
    final net = back - staked;
    Color tone(num v) => v >= 0 ? scheme.primary : scheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Résultat à mise fixe'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in const [500, 1000, 5000])
                      ChoiceChip(
                          label: Text(money(s, currency: cur)),
                          selected: _stake == s,
                          onSelected: (_) => setState(() => _stake = s)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                    'Avec ${money(_stake, currency: cur)} sur chacun des $settled coupons réglés :',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _cell(context, 'Misé', money(staked, currency: cur)),
                    _cell(context, 'Retourné', money(back, currency: cur)),
                    _cell(context, 'Net', signedMoney(net, currency: cur),
                        color: tone(net)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Rendement : ${_signedPct(_dn(p['theoretical_return']))}',
                    style:
                        theme.textTheme.labelLarge?.copyWith(color: tone(net))),
                const Divider(height: 24),
                for (final r in _rows(p['by_category']))
                  if (_i(r['settled']) > 0)
                    Builder(builder: (context) {
                      final n = _i(r['settled']);
                      final b = ((_dn(r['returned']) ?? 0) * _stake).round();
                      final rowNet = b - n * _stake;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                  '${categoryLabels[r['key']] ?? r['key']} · $n réglés'),
                            ),
                            Text(signedMoney(rowNet, currency: cur),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tone(rowNet))),
                          ],
                        ),
                      );
                    }),
                const SizedBox(height: 8),
                Text(
                    'Calcul théorique sur les cotes publiées : coupon gagnant = mise × cote réglée, perdant = mise perdue. '
                    'Aucun pari réel. Les résultats passés ne préjugent pas des suivants.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, String head, String value,
      {Color? color}) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Calibration : pour chaque tranche de probabilité annoncée par le modèle, la fréquence réelle
/// constatée. Un modèle fiable donne deux barres proches.
class CalibrationChart extends StatelessWidget {
  const CalibrationChart({super.key, required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget bar(double v, Color color) => LayoutBuilder(
          builder: (context, c) => Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 10,
              width: c.maxWidth * v.clamp(0, 1),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(5)),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Calibration : annoncé contre constaté'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 14, runSpacing: 4, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, color: scheme.outline),
                    const SizedBox(width: 6),
                    const Text('Annoncé par le modèle'),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, color: scheme.primary),
                    const SizedBox(width: 6),
                    const Text('Constaté'),
                  ]),
                ]),
                const SizedBox(height: 12),
                for (final r in rows)
                  Builder(builder: (context) {
                    final low = ((_dn(r['bucket']) ?? 0) * 100).round();
                    final n = _i(r['selections']);
                    final predicted = _dn(r['predicted']) ?? 0;
                    final observed = _dn(r['observed']) ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text('$low–${low + 10} %',
                                  style: theme.textTheme.labelLarge),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    textAlign: TextAlign.end,
                                    '${_rate(predicted)} → ${_rate(observed)} · $n sél.${n < 20 ? ' (peu de données)' : ''}',
                                    style: theme.textTheme.labelSmall),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          bar(predicted, scheme.outline),
                          const SizedBox(height: 3),
                          bar(observed, scheme.primary),
                        ],
                      ),
                    );
                  }),
                Text(
                    'Sélections des coupons publiés, réglées sur le score à 90 minutes. Quand les deux barres se '
                    'ressemblent, les pourcentages annoncés sont fiables ; un écart signale une estimation trop '
                    'optimiste ou trop prudente.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
