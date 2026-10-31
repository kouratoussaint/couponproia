import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../billing/billing_screen.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';

/// Console d'administration : chaque section n'apparaît qu'avec la permission correspondante,
/// et chaque action est de toute façon vérifiée par le serveur.
class AdminConsoleScreen extends ConsumerStatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  ConsumerState<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends ConsumerState<AdminConsoleScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('admin.access')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administration')),
        body: const InfoMessage(
            icon: Icons.lock_outline, title: 'Accès réservé à l’équipe'),
      );
    }
    final dash = ref.watch(adminDashboardProvider(_days));
    final sections = <(String, IconData, String, String)>[
      if (perms.contains('users.manage'))
        (
          'Utilisateurs',
          Icons.people_outline,
          'Rôles, suspension, crédits, abonnements',
          AppRoutes.adminUsers
        ),
      if (perms.contains('generation.manage'))
        (
          'Coupons et générations',
          Icons.auto_mode,
          'Validation, publication, profils',
          AppRoutes.generationsAdmin
        ),
      if (perms.contains('ai.configure'))
        (
          'Moteur et IA',
          Icons.psychology_outlined,
          'Évaluation, prompts, fournisseurs',
          AppRoutes.engineAdmin
        ),
      if (perms.contains('sports.configure'))
        (
          'Données sportives',
          Icons.sync_alt,
          'Compétitions, synchronisations, quotas',
          AppRoutes.sportsAdmin
        ),
      if (perms.contains('flags.manage'))
        (
          'Modules',
          Icons.toggle_on_outlined,
          'Activer ou désactiver sans nouvelle version',
          AppRoutes.adminFlags
        ),
      if (perms.contains('settings.manage'))
        (
          'Réglages et forfaits',
          Icons.tune,
          'Prix, crédits, quotas, limites',
          AppRoutes.adminSettings
        ),
      if (perms.contains('billing.manage'))
        (
          'Paiements',
          Icons.payments_outlined,
          'Transactions Mobile Money',
          AppRoutes.adminPayments
        ),
      if (perms.contains('moderation.manage'))
        (
          'Modération',
          Icons.shield_outlined,
          'Signalements de la communauté',
          AppRoutes.moderation
        ),
      if (perms.contains('audit.read'))
        (
          'Journal d’audit',
          Icons.history,
          'Toutes les actions sensibles',
          AppRoutes.adminAudit
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminDashboardProvider(_days));
          await ref.read(adminDashboardProvider(_days).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('24 h')),
                ButtonSegment(value: 7, label: Text('7 j')),
                ButtonSegment(value: 30, label: Text('30 j')),
                ButtonSegment(value: 90, label: Text('90 j')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: 8),
            dash.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text(userMessageFor(e)),
              data: (d) => DashboardView(data: d),
            ),
            const SectionTitle('Gestion'),
            for (final (title, icon, subtitle, route) in sections)
              Card(
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(title),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(route),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = asMap(data['users']);
    final coupons = asMap(data['coupons']);
    final ai = asMap(data['ai']);
    final billing = asMap(data['billing']);
    final community = asMap(data['community']);
    final sports = asMap(data['data']);
    final errors = asMap(data['errors']);
    final payments = asMap(billing['payments']);
    final daily = asList(data['daily']);
    final totalErrors = errors.values.fold<int>(0, (a, b) => a + asInt(b));

    Widget group(String title, List<(String, String)> tiles, {Color? accent}) =>
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: accent)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    for (final (label, value) in tiles)
                      SizedBox(
                        width: 104,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(value,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text(label, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        group('Utilisateurs', [
          ('au total', '${users['total']}'),
          ('nouveaux', '${users['new']}'),
          ('actifs', '${users['active']}'),
          ('Tipsters', '${users['tipsters']}'),
          ('suspendus', '${users['suspended']}'),
        ]),
        group('Coupons', [
          ('générés', '${coupons['generated']}'),
          ('publiés', '${coupons['published']}'),
          ('gagnés', '${coupons['won']}'),
          ('perdus', '${coupons['lost']}'),
          ('à valider', '${coupons['pending_review']}'),
          ('publiés par Tipsters', '${coupons['tipster_published']}'),
        ]),
        group('IA et crédits', [
          ('appels IA', '${ai['requests']}'),
          ('analyses', '${ai['match_analyses']}'),
          (
            'coût estimé',
            '${(ai['cost_usd'] as num? ?? 0).toStringAsFixed(2)} \$'
          ),
          ('crédits consommés', '${ai['credits_consumed']}'),
          ('erreurs IA', '${ai['errors']}'),
        ]),
        group('Ventes', [
          ('revenus', fcfa(asInt(billing['revenue_xof']))),
          ('abonnements actifs', '${billing['active_subscriptions']}'),
          ('paiements confirmés', '${payments['succeeded'] ?? 0}'),
          ('en attente', '${payments['pending'] ?? 0}'),
          ('échoués', '${payments['failed'] ?? 0}'),
        ]),
        group('Données et communauté', [
          ('requêtes API', '${sports['requests_used']}'),
          ('dont aujourd’hui', '${sports['requests_today']}'),
          ('restantes', '${sports['requests_remaining'] ?? '–'}'),
          ('publications', '${community['posts']}'),
          ('signalements ouverts', '${community['open_reports']}'),
        ]),
        group(
          totalErrors == 0
              ? 'Erreurs : aucune'
              : 'Erreurs système : $totalErrors',
          [
            ('IA', '${errors['ai']}'),
            ('synchronisation', '${errors['sync']}'),
            ('génération', '${errors['generation']}'),
            ('paiements', '${errors['payments']}'),
          ],
          accent: totalErrors == 0 ? null : theme.colorScheme.error,
        ),
        if (daily.isNotEmpty) _DailyChart(daily: daily),
      ],
    );
  }
}

/// Nouveaux utilisateurs par jour (barres simples).
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.daily});

  final List<Map<String, dynamic>> daily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [for (final d in daily) asInt(d['new_users'])];
    final max = values.fold<int>(1, (a, b) => b > a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveaux utilisateurs par jour',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in values)
                    Expanded(
                      child: Tooltip(
                        message: '$v',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: v == 0 ? 2 : 86 * v / max,
                          decoration: BoxDecoration(
                            color: v == 0
                                ? theme.colorScheme.outlineVariant
                                : theme.colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text('Maximum : $max par jour', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
