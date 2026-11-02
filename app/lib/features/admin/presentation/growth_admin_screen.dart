import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../simulator/data/stake_math.dart';
import '../../system/system_providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

final growthProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, days) async {
  final res = await ref
      .watch(supabaseClientProvider)
      .rpc('admin_growth', params: {'p_days': days});
  return Map<String, dynamic>.from(res as Map);
});

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

/// Part en pourcentage, « — » sans base.
String share(int n, int of) => of == 0 ? '—' : pct(n / of);

/// Console → Conversion et rétention.
class GrowthAdminScreen extends ConsumerStatefulWidget {
  const GrowthAdminScreen({super.key});

  @override
  ConsumerState<GrowthAdminScreen> createState() => _GrowthAdminScreenState();
}

class _GrowthAdminScreenState extends ConsumerState<GrowthAdminScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('growth.read')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Conversion et rétention'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Écran réservé au super administrateur')),
      );
    }
    final theme = Theme.of(context);
    final data = ref.watch(growthProvider(_days));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Conversion et rétention'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(growthProvider(_days)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final d in const [7, 30, 90])
                  ChoiceChip(
                      label: Text(trf('{0} jours', [d])),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d)),
              ],
            ),
            ...data.when(
              loading: () => [
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: LinearProgressIndicator())
              ],
              error: (e, _) => [Text(userMessageFor(e))],
              data: (g) => _content(context, theme, g),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
      BuildContext context, ThemeData theme, Map<String, dynamic> g) {
    final f = _m(g['funnel']);
    final p = _m(g['period']);
    final a = _m(g['active']);
    final signed = _i(f['signed_up']);
    final steps = [
      (tr('Inscrits'), _i(f['signed_up'])),
      (tr('Premier lancement terminé'), _i(f['onboarded'])),
      (tr('Revenus un autre jour'), _i(f['came_back'])),
      (tr('Premier achat'), _i(f['first_purchase'])),
      (tr('Abonnement renouvelé'), _i(f['renewed'])),
    ];
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return [
      SectionTitle(tr('Utilisateurs actifs')),
      Row(children: [
        _Kpi(tr('Aujourd’hui'), '${_i(a['day'])}'),
        _Kpi(tr('7 jours'), '${_i(a['week'])}'),
        _Kpi(tr('30 jours'), '${_i(a['month'])}'),
      ]),
      SectionTitle(trf('Entonnoir des inscrits ({0} derniers jours)', [_days])),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (label, n) in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(label)),
                        Text('$n · ${share(n, signed)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: signed == 0 ? 0 : n / signed, minHeight: 8),
                      ),
                    ],
                  ),
                ),
              Text(
                  tr('Utilisateurs inscrits pendant la période, et ce qu’ils ont fait depuis.'),
                  style: muted),
            ],
          ),
        ),
      ),
      SectionTitle(tr('Sur la période')),
      Card(
        child: Column(children: [
          _Line(tr('Nouveaux clients payants'), '${_i(p['new_paying'])}'),
          _Line(tr('Renouvellements d’abonnement'), '${_i(p['renewals'])}'),
          _Line(tr('Revenus encaissés'), money(_i(p['revenue_xof']))),
          _Line(
              tr('Forfaits payants en cours'),
              trf('{0} sur {1} ({2})', [
                _i(p['paying_now']),
                _i(p['users_total']),
                share(_i(p['paying_now']), _i(p['users_total']))
              ])),
          _Line(
              tr('Liens partagés ouverts'),
              trf('{0} (dont {1} sur Android)',
                  [_i(p['share_opens']), _i(p['share_opens_android'])])),
        ]),
      ),
      SectionTitle(tr('Rétention par semaine d’inscription')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(1.3)},
            children: [
              TableRow(children: [
                for (final h in [
                  tr('Semaine'),
                  tr('Inscrits'),
                  'J7',
                  'J30',
                  tr('Payants')
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(h, style: theme.textTheme.labelMedium),
                  ),
              ]),
              for (final c in (g['cohorts'] as List? ?? const []).reversed)
                () {
                  final r = _m(c);
                  final week =
                      '${r['week']}'.substring(5).split('-').reversed.join('/');
                  final users = _i(r['users']);
                  return TableRow(children: [
                    Text(trf('du {0}', [week])),
                    Text('$users'),
                    Text(_i(r['d7_eligible']) == 0
                        ? '…'
                        : share(_i(r['d7']), _i(r['d7_eligible']))),
                    Text(_i(r['d30_eligible']) == 0
                        ? '…'
                        : share(_i(r['d30']), _i(r['d30_eligible']))),
                    Text(share(_i(r['paid']), users)),
                  ]);
                }(),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
            tr('J7 / J30 : part des inscrits de la semaine revenus dans l’app au moins une fois 7 (30) jours ou plus après leur inscription (« … » : trop récent pour le savoir). Activité comptée à chaque ouverture de l’app depuis la version 0.25.0 ; avant, d’après les traces existantes (connexions, analyses, assistant, carnet).'),
            style: muted),
      ),
    ];
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing:
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
