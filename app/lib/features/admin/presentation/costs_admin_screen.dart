import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../billing/billing_screen.dart';
import '../data/admin_repository.dart';
import 'admin_console_screen.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Taille lisible (o, Ko, Mo, Go).
String bytesLabel(int bytes) {
  final units = ['o', tr('Ko'), tr('Mo'), tr('Go')];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', decimalSeparator)} ${units[i]}';
}

String _usd(Object? v, int digits) =>
    '${(v as num? ?? 0).toStringAsFixed(digits).replaceAll('.', decimalSeparator)} \$';

final _aiKinds = {
  'match_analysis': tr('Analyses de match'),
  'coupon_summary': tr('Résumés de coupons'),
  'assistant_intent': tr('Assistant (compréhension)'),
  'engine_evaluation': tr('Évaluation du moteur'),
  'provider_test': tr('Tests des fournisseurs'),
};

/// Coûts de fonctionnement et coût moyen par utilisateur actif.
/// Mesuré : IA, commissions de paiement ; renseigné : abonnements fixes (réglages « costs.* »).
class CostsAdminScreen extends ConsumerStatefulWidget {
  const CostsAdminScreen({super.key});

  @override
  ConsumerState<CostsAdminScreen> createState() => _CostsAdminScreenState();
}

class _CostsAdminScreenState extends ConsumerState<CostsAdminScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final costs = ref.watch(adminCostsProvider(_days));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Coûts'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminCostsProvider(_days)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 7, label: Text(tr('7 j'))),
                ButtonSegment(value: 30, label: Text(tr('30 j'))),
                ButtonSegment(value: 90, label: Text(tr('90 j'))),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: 8),
            costs.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text(userMessageFor(e)),
              data: (d) => CostsView(data: d),
            ),
          ],
        ),
      ),
    );
  }
}

class CostsView extends StatelessWidget {
  const CostsView({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ai = asMap(data['ai']);
    final fixed = asMap(data['fixed']);
    final payments = asMap(data['payments']);
    final sports = asMap(data['sports']);
    final notifs = asMap(data['notifications']);
    final storage = asMap(data['storage']);
    final perUser = data['per_active_user_xof'];
    final margin = asInt(data['margin_xof']);
    final fixedItems = asMap(fixed['items']);
    final small = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGroup(
          title: trf('Sur {0} jours', [data['days']]),
          tiles: [
            (tr('coût total estimé'), fcfa(asInt(data['total_xof']))),
            (
              tr('par utilisateur actif'),
              perUser == null ? '–' : fcfa(asInt(perUser))
            ),
            (tr('utilisateurs actifs'), '${data['active_users']}'),
            ('revenus', fcfa(asInt(data['revenue_xof']))),
            (
              margin >= 0 ? tr('excédent') : tr('déficit'),
              fcfa(margin.abs()),
            ),
          ],
          accent: theme.colorScheme.primary,
          footer: fixed['configured'] == true
              ? null
              : Text(
                  tr('Abonnements fixes non renseignés : le total ne compte que l’IA et les commissions. Renseigner « costs.fixed_monthly_xof » dans Réglages.'),
                  style: small?.copyWith(color: theme.colorScheme.error)),
        ),
        MetricGroup(
          title: tr('Intelligence artificielle (mesuré)'),
          tiles: [
            (tr('coût'), fcfa(asInt(ai['cost_xof']))),
            (tr('en dollars'), _usd(ai['cost_usd'], 2)),
            (tr('appels'), '${ai['requests']}'),
            if (asInt(ai['unpriced']) > 0)
              (tr('sans prix connu'), '${ai['unpriced']}'),
          ],
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final k in asList(ai['by_kind']))
                Text(
                    trf('{0} : {1} appels · {2}', [
                      _aiKinds[k['kind']] ?? k['kind'],
                      k['requests'],
                      _usd(k['cost_usd'], 3)
                    ]),
                    style: small),
              Text(
                  trf('Prix par million de jetons : réglage « ai.pricing_usd_per_mtok ». Conversion : 1 \$ = {0} FCFA (« costs.usd_to_xof »).',
                      [data['usd_to_xof']]),
                  style: small),
            ],
          ),
        ),
        MetricGroup(
          title: tr('Abonnements fixes (renseigné)'),
          tiles: [
            (tr('par mois'), fcfa(asInt(fixed['monthly_xof']))),
            (tr('sur la période'), fcfa(asInt(fixed['period_xof']))),
          ],
          footer: fixedItems.isEmpty
              ? null
              : Text(
                  [
                    for (final e in fixedItems.entries)
                      '${e.key} : ${fcfa(asInt(e.value))}'
                  ].join(' · '),
                  style: small),
        ),
        MetricGroup(
          title: tr('Paiements'),
          tiles: [
            ('commissions', fcfa(asInt(payments['fees_xof']))),
            (tr('taux'), '${payments['fee_percent']} %'),
            (tr('paiements'), '${payments['count']}'),
          ],
        ),
        MetricGroup(
          title: tr('Données sportives'),
          tiles: [
            (tr('requêtes'), '${sports['requests']}'),
            (tr('par jour'), '${sports['requests_per_day']}'),
            (
              tr('restantes aujourd’hui'),
              '${sports['remaining_today'] ?? '–'}'
            ),
          ],
          footer: Text(
              tr('Inclus dans l’abonnement API-Football (montant fixe ci-dessus).'),
              style: small),
        ),
        MetricGroup(
          title: tr('Notifications'),
          tiles: [
            (tr('créées'), '${notifs['created']}'),
            (tr('envoyées au téléphone'), '${notifs['sent']}'),
            (tr('échecs'), '${notifs['failed']}'),
          ],
          footer: Text(tr('Firebase Cloud Messaging : sans frais par message.'),
              style: small),
        ),
        MetricGroup(
          title: tr('Stockage'),
          tiles: [
            (
              tr('base de données'),
              bytesLabel(asInt(storage['database_bytes']))
            ),
            for (final f in asList(storage['files']))
              (
                '${f['bucket']} (${f['objects']})',
                bytesLabel(asInt(f['bytes']))
              ),
          ],
          footer: Text(
              tr('La bande passante n’est pas mesurée ici : voir le tableau de bord Supabase (Usage).'),
              style: small),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push(AppRoutes.adminSettings),
            icon: const Icon(Icons.tune),
            label: Text(tr('Modifier les montants (réglages « costs. »)')),
          ),
        ),
        Text(
            tr('Estimations : prix publics des modèles IA, montants saisis par l’administrateur. Les quotas et tarifs des fournisseurs peuvent changer.'),
            style: small),
      ],
    );
  }
}
