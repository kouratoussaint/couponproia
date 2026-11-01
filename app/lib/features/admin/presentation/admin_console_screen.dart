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

/// Couleurs de la console, une par famille (mêmes teintes en clair et en sombre).
abstract final class ConsoleColors {
  static const users = Color(0xFF2563EB);
  static const coupons = Color(0xFF00875A);
  static const ai = Color(0xFF7C3AED);
  static const engine = Color(0xFF9333EA);
  static const sports = Color(0xFF0891B2);
  static const money = Color(0xFFC27C0E);
  static const promo = Color(0xFFDB2777);
  static const costs = Color(0xFFEA580C);
  static const errors = Color(0xFFD94C4C);
  static const settings = Color(0xFF334155);
  static const modules = Color(0xFF0E1B4D);
  static const legal = Color(0xFF7C5E3C);
  static const audit = Color(0xFF55635D);
  static const navy = Color(0xFF0E1B4D);
}

/// Entrée de la console : titre, description, icône, couleur, écran, compteur d'attente.
class ConsoleEntry {
  const ConsoleEntry(
      this.title, this.subtitle, this.icon, this.color, this.route,
      {this.badge = 0});

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
  final int badge;
}

class _AdminConsoleScreenState extends ConsumerState<AdminConsoleScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('admin.access')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Console d’administration')),
        body: const InfoMessage(
            icon: Icons.lock_outline, title: 'Accès réservé à l’équipe'),
      );
    }
    final dash = ref.watch(adminDashboardProvider(_days));
    final d = dash.valueOrNull ?? const <String, dynamic>{};
    final coupons = asMap(d['coupons']);
    final community = asMap(d['community']);
    final payments = asMap(asMap(d['billing'])['payments']);
    final families = <(String, List<ConsoleEntry>)>[
      (
        'Pilotage',
        [
          if (perms.contains('users.manage'))
            const ConsoleEntry(
                'Utilisateurs',
                'Fiches, forfaits, crédits, rôles',
                Icons.people_alt_outlined,
                ConsoleColors.users,
                AppRoutes.adminUsers),
          if (perms.contains('generation.manage'))
            ConsoleEntry(
                'Coupons et générations',
                'Validation, publication, profils',
                Icons.confirmation_number_outlined,
                ConsoleColors.coupons,
                AppRoutes.generationsAdmin,
                badge: asInt(coupons['pending_review'])),
          if (perms.contains('featured.manage'))
            const ConsoleEntry(
                'Analyse offerte',
                'Choisir le match du jour',
                Icons.card_giftcard,
                ConsoleColors.money,
                AppRoutes.adminFeatured),
          if (perms.contains('moderation.manage'))
            ConsoleEntry(
                'Modération',
                'Signalements de la communauté',
                Icons.shield_outlined,
                ConsoleColors.errors,
                AppRoutes.moderation,
                badge: asInt(community['open_reports'])),
          if (perms.contains('audit.read'))
            const ConsoleEntry(
                'Journal d’audit',
                'Toutes les actions sensibles',
                Icons.history,
                ConsoleColors.audit,
                AppRoutes.adminAudit),
        ]
      ),
      (
        'IA et données',
        [
          if (perms.contains('ai.providers'))
            const ConsoleEntry(
                'Fournisseurs d’IA',
                'Principale, secours, quotas',
                Icons.hub_outlined,
                ConsoleColors.ai,
                AppRoutes.adminAi),
          if (perms.contains('ai.configure'))
            const ConsoleEntry(
                'Moteur et IA',
                'Évaluation, prompts, journal',
                Icons.psychology_outlined,
                ConsoleColors.engine,
                AppRoutes.engineAdmin),
          if (perms.contains('sports.configure'))
            const ConsoleEntry(
                'Données sportives',
                'Compétitions, synchronisations',
                Icons.sync_alt,
                ConsoleColors.sports,
                AppRoutes.sportsAdmin),
        ]
      ),
      (
        'Argent',
        [
          if (perms.contains('billing.manage')) ...[
            ConsoleEntry(
                'Paiements',
                'LigdiCash, CinetPay, remboursements',
                Icons.payments_outlined,
                ConsoleColors.money,
                AppRoutes.adminPayments,
                badge: asInt(payments['pending'])),
            const ConsoleEntry(
                'Codes promo',
                'Réductions et durée',
                Icons.local_offer_outlined,
                ConsoleColors.promo,
                AppRoutes.adminPromos),
            const ConsoleEntry('Coûts', 'Coût par utilisateur actif',
                Icons.query_stats, ConsoleColors.costs, AppRoutes.adminCosts),
          ],
        ]
      ),
      (
        'Plateforme',
        [
          if (perms.contains('settings.manage'))
            const ConsoleEntry('Réglages et forfaits', 'Prix, crédits, limites',
                Icons.tune, ConsoleColors.settings, AppRoutes.adminSettings),
          if (perms.contains('flags.manage'))
            const ConsoleEntry(
                'Modules',
                'Activer sans nouvelle version',
                Icons.toggle_on_outlined,
                ConsoleColors.modules,
                AppRoutes.adminFlags),
          if (perms.contains('settings.manage'))
            const ConsoleEntry(
                'Documents légaux',
                'CGU, confidentialité, règles',
                Icons.description_outlined,
                ConsoleColors.legal,
                AppRoutes.adminLegal),
        ]
      ),
    ];
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: ConsoleColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        title: const Text('Console d’administration'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                    perms.contains('ai.providers')
                        ? 'Super admin'
                        : 'Administrateur',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminDashboardProvider(_days));
          await ref.read(adminDashboardProvider(_days).future);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ConsoleHeader(
              days: _days,
              onDays: (v) => setState(() => _days = v),
              data: dash.valueOrNull,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dash.when(
                    loading: () => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text(userMessageFor(e)),
                    data: (d) => DashboardView(data: d),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Gestion',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  for (final (title, entries) in families)
                    if (entries.isNotEmpty)
                      ConsoleFamily(title: title, entries: entries),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// En-tête bleu nuit : période et trois chiffres clés.
class ConsoleHeader extends StatelessWidget {
  const ConsoleHeader(
      {super.key,
      required this.days,
      required this.onDays,
      required this.data});

  final int days;
  final ValueChanged<int> onDays;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = data;
    final kpis = [
      (
        d == null ? '–' : '${asMap(d['users'])['active'] ?? 0}',
        'utilisateurs actifs'
      ),
      (
        d == null ? '–' : '${asMap(d['coupons'])['published'] ?? 0}',
        'coupons publiés'
      ),
      (
        d == null ? '–' : fcfa(asInt(asMap(d['billing'])['revenue_xof'])),
        'revenus'
      ),
    ];
    const periods = [(1, '24 h'), (7, '7 j'), (30, '30 j'), (90, '90 j')];
    return Container(
      color: ConsoleColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (final (v, label) in periods)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => onDays(v),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        constraints: const BoxConstraints(minHeight: 34),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: v == days ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(label,
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: v == days
                                    ? ConsoleColors.navy
                                    : Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < kpis.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(kpis[i].$1,
                              style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ),
                        Text(kpis[i].$2,
                            maxLines: 2,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: const Color(0xFFB9C3E8))),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Une famille de la gestion : tuiles de couleur, deux par ligne, compteur d'attente en rouge.
class ConsoleFamily extends StatelessWidget {
  const ConsoleFamily({super.key, required this.title, required this.entries});

  final String title;
  final List<ConsoleEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in entries)
                SizedBox(
                  width: w,
                  child: Material(
                    color: scheme.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push(e.route),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: e.color,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(e.icon,
                                      color: Colors.white, size: 21),
                                ),
                                const Spacer(),
                                if (e.badge > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: ConsoleColors.errors,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text('${e.badge}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(e.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(e.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
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
    final won = asInt(coupons['won']), lost = asInt(coupons['lost']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGroup(
          title: 'Utilisateurs',
          icon: Icons.people_alt_outlined,
          color: ConsoleColors.users,
          badge: asInt(users['new']) > 0
              ? '+${users['new']} sur la période'
              : null,
          tiles: [
            ('au total', '${users['total']}', Icons.groups_outlined),
            ('nouveaux', '${users['new']}', Icons.person_add_alt),
            ('actifs', '${users['active']}', Icons.monitor_heart_outlined),
            ('Tipsters', '${users['tipsters']}', Icons.star_outline),
            ('suspendus', '${users['suspended']}', Icons.block),
          ],
        ),
        MetricGroup(
          title: 'Coupons',
          icon: Icons.confirmation_number_outlined,
          color: ConsoleColors.coupons,
          badge: won + lost > 0
              ? '$won gagné${won > 1 ? 's' : ''} · $lost perdu${lost > 1 ? 's' : ''}'
              : null,
          tiles: [
            ('générés', '${coupons['generated']}', Icons.auto_awesome),
            ('publiés', '${coupons['published']}', Icons.send_outlined),
            ('gagnés', '${coupons['won']}', Icons.check_circle_outline),
            ('perdus', '${coupons['lost']}', Icons.cancel_outlined),
            ('à valider', '${coupons['pending_review']}', Icons.schedule),
            (
              'par les Tipsters',
              '${coupons['tipster_published']}',
              Icons.forum_outlined
            ),
          ],
        ),
        MetricGroup(
          title: 'IA et crédits',
          icon: Icons.auto_awesome,
          color: ConsoleColors.ai,
          badge:
              '${(ai['cost_usd'] as num? ?? 0).toStringAsFixed(2).replaceAll('.', ',')} \$',
          tiles: [
            ('appels IA', '${ai['requests']}', Icons.bolt),
            ('analyses', '${ai['match_analyses']}', Icons.psychology_outlined),
            (
              'crédits utilisés',
              '${ai['credits_consumed']}',
              Icons.toll_outlined
            ),
            ('erreurs IA', '${ai['errors']}', Icons.error_outline),
          ],
        ),
        MetricGroup(
          title: 'Ventes',
          icon: Icons.payments_outlined,
          color: ConsoleColors.money,
          tiles: [
            (
              'revenus',
              fcfa(asInt(billing['revenue_xof'])),
              Icons.account_balance_wallet_outlined
            ),
            (
              'abonnements',
              '${billing['active_subscriptions']}',
              Icons.workspace_premium_outlined
            ),
            (
              'confirmés',
              '${payments['succeeded'] ?? 0}',
              Icons.check_circle_outline
            ),
            ('en attente', '${payments['pending'] ?? 0}', Icons.schedule),
            ('échoués', '${payments['failed'] ?? 0}', Icons.cancel_outlined),
          ],
        ),
        MetricGroup(
          title: 'Données et communauté',
          icon: Icons.storage_outlined,
          color: ConsoleColors.sports,
          tiles: [
            ('requêtes API', '${sports['requests_used']}', Icons.sync_alt),
            (
              'aujourd’hui',
              '${sports['requests_today']}',
              Icons.today_outlined
            ),
            (
              'restantes',
              '${sports['requests_remaining'] ?? '–'}',
              Icons.hourglass_bottom
            ),
            ('publications', '${community['posts']}', Icons.forum_outlined),
            (
              'signalements',
              '${community['open_reports']}',
              Icons.flag_outlined
            ),
          ],
        ),
        MetricGroup(
          title: 'Erreurs système',
          icon: Icons.warning_amber_rounded,
          color: ConsoleColors.errors,
          badge: totalErrors == 0 ? 'aucune' : '$totalErrors',
          tiles: [
            ('IA', '${errors['ai']}', Icons.auto_awesome),
            ('synchro', '${errors['sync']}', Icons.sync_alt),
            (
              'génération',
              '${errors['generation']}',
              Icons.confirmation_number_outlined
            ),
            ('paiements', '${errors['payments']}', Icons.payments_outlined),
          ],
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

/// Carte de chiffres clés en couleur : en-tête avec icône, pastilles (icône, valeur, libellé).
/// Les tuiles acceptent (libellé, valeur) ou (libellé, valeur, icône).
class MetricGroup extends StatelessWidget {
  const MetricGroup(
      {super.key,
      required this.title,
      required this.tiles,
      this.accent,
      this.footer,
      this.icon,
      this.color,
      this.badge});

  final String title;
  final List<Record> tiles;
  final Color? accent;
  final Widget? footer;
  final IconData? icon;
  final Color? color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = color ?? accent ?? scheme.primary;
    final dark = theme.brightness == Brightness.dark;
    final tint = c.withValues(alpha: dark ? 0.20 : 0.10);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: c, width: 4))),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: tint, borderRadius: BorderRadius.circular(11)),
                  child:
                      Icon(icon ?? Icons.insights_outlined, size: 18, color: c),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800, color: accent)),
                ),
                if (badge != null)
                  Flexible(
                    child: Text(badge!,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: c, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(12)),
                        child: _TileContent(tile: tile, color: c),
                      ),
                    ),
                ],
              );
            }),
            if (footer != null) ...[const SizedBox(height: 10), footer!],
          ],
        ),
      ),
    );
  }
}

class _TileContent extends StatelessWidget {
  const _TileContent({required this.tile, required this.color});

  final Record tile;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, value, icon) = switch (tile) {
      (String l, String v, IconData i) => (l, v, i as IconData?),
      (String l, String v) => (l, v, null),
      _ => ('', '', null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
