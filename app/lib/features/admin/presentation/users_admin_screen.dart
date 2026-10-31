import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../billing/billing_screen.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';

const roleLabels = {
  'user': 'Utilisateur',
  'subscriber': 'Abonné',
  'tipster': 'Tipster',
  'moderator': 'Modérateur',
  'admin': 'Administrateur',
  'super_admin': 'Super administrateur',
};

String _date(String? iso) {
  if (iso == null) return '–';
  final d = DateTime.parse(iso).toLocal();
  return '${shortDate(d)}/${d.year} ${timeLabel(d)}';
}

class UsersAdminScreen extends ConsumerStatefulWidget {
  const UsersAdminScreen({super.key});

  @override
  ConsumerState<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends ConsumerState<UsersAdminScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'E-mail, nom ou identifiant'),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          ...users.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(adminErrorMessage(e))],
            data: (list) => list.isEmpty
                ? [
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun utilisateur trouvé.'))
                  ]
                : [
                    for (final u in list)
                      Card(
                        child: ListTile(
                          leading: Icon(u['suspended'] == true
                              ? Icons.block
                              : Icons.person_outline),
                          title: Text(
                              u['display_name'] as String? ?? '(sans nom)'),
                          subtitle: Text([
                            u['email'] as String? ?? '',
                            '${u['plan']} · ${(u['roles'] as List).where((r) => r != 'user').map((r) => roleLabels[r] ?? r).join(', ')}',
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context
                              .push(AppRoutes.adminUserFor(u['id'] as String)),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class UserAdminDetailScreen extends ConsumerWidget {
  const UserAdminDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(adminUserProvider(userId));
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final plans = [
      for (final p in (ref
              .watch(publicSettingsProvider)
              .valueOrNull?['pricing.plans'] as List? ??
          const []))
        (p as Map)['code'] as String,
    ];

    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        ref.invalidate(adminUserProvider(userId));
        ref.invalidate(adminUsersProvider);
        if (context.mounted) showMessage(context, done);
      } catch (e) {
        if (context.mounted) {
          showMessage(context, adminErrorMessage(e), error: true);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fiche utilisateur')),
      body: user.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.lock_outline,
            title: 'Indisponible',
            body: adminErrorMessage(e)),
        data: (u) {
          final roles = {for (final r in (u['roles'] as List)) r as String};
          final credits = asMap(u['credits']);
          final activity = asMap(u['activity']);
          final repo = ref.read(adminRepositoryProvider);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminUserProvider(userId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u['display_name'] as String? ?? '(sans nom)',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        SelectableText(u['email'] as String? ?? ''),
                        const SizedBox(height: 6),
                        Text(
                            'Inscrit le ${_date(u['created_at'] as String?)} · dernière connexion ${_date(u['last_sign_in_at'] as String?)}',
                            style: theme.textTheme.bodySmall),
                        Text(
                            'Forfait ${u['plan']} · crédits ${credits['unlimited'] == true ? 'illimités' : credits['total']}',
                            style: theme.textTheme.bodyMedium),
                        if (u['tipster'] != null)
                          Text(
                              'Tipster @${asMap(u['tipster'])['handle']} (${asMap(u['tipster'])['status']})',
                              style: theme.textTheme.bodySmall),
                        if (u['suspended'] == true)
                          Text('Compte suspendu',
                              style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w700)),
                        TextButton.icon(
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: userId)),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copier l’identifiant'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Rôles'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in roleLabels.keys.where((r) => r != 'user'))
                      FilterChip(
                        label: Text(roleLabels[r]!),
                        selected: roles.contains(r),
                        onSelected: (r == 'admin' || r == 'super_admin') &&
                                !perms.contains('admins.manage')
                            ? null
                            : (on) => run(() => repo.setRole(userId, r, on),
                                on ? 'Rôle ajouté.' : 'Rôle retiré.'),
                      ),
                  ],
                ),
                const SectionTitle('Actions'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (perms.contains('billing.manage')) ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          final r = await _creditsDialog(context);
                          if (r != null) {
                            await run(
                                () => repo.adjustCredits(userId, r.$1, r.$2),
                                'Crédits ajustés.');
                          }
                        },
                        icon: const Icon(Icons.bolt),
                        label: const Text('Ajuster les crédits'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final r = await _subscriptionDialog(context,
                              plans.where((p) => p != 'FREE').toList());
                          if (r != null) {
                            await run(
                                () => repo.grantSubscription(
                                    userId, r.$1, r.$2, r.$3),
                                'Abonnement accordé.');
                          }
                        },
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('Offrir un abonnement'),
                      ),
                    ],
                    u['suspended'] == true
                        ? FilledButton.icon(
                            onPressed: () => run(
                                () => repo.setSuspended(userId, false),
                                'Compte réactivé.'),
                            icon: const Icon(Icons.lock_open),
                            label: const Text('Réactiver'),
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error),
                            onPressed: () async {
                              if (await _confirm(
                                  context,
                                  'Suspendre ce compte ?',
                                  'La personne ne pourra plus utiliser ses droits ni publier.')) {
                                await run(() => repo.setSuspended(userId, true),
                                    'Compte suspendu.');
                              }
                            },
                            icon: const Icon(Icons.block),
                            label: const Text('Suspendre'),
                          ),
                  ],
                ),
                const SectionTitle('Activité'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text([
                      'Analyses (30 j) : ${activity['analyses_30d']}',
                      'Messages à l’assistant (30 j) : ${activity['assistant_messages_30d']}',
                      'Coupons enregistrés : ${activity['saved_coupons']} · publiés : ${activity['published_coupons']}',
                      'Publications : ${activity['posts']} · commentaires : ${activity['comments']}',
                      'Signalements le concernant : ${activity['reports_against']}',
                    ].join('\n')),
                  ),
                ),
                _ListSection(
                  title: 'Abonnements',
                  rows: [
                    for (final s in asList(u['subscriptions']))
                      '${s['plan']} · ${_date(s['start'] as String?)} → ${_date(s['end'] as String?)} (${s['source']})',
                  ],
                ),
                _ListSection(
                  title: 'Paiements',
                  rows: [
                    for (final p in asList(u['payments']))
                      '${_date(p['created_at'] as String?)} · ${fcfa(asInt(p['amount_xof']))} · ${p['kind']} · ${p['status']}',
                  ],
                ),
                _ListSection(
                  title: 'Mouvements de crédits',
                  rows: [
                    for (final l in asList(u['ledger']))
                      '${_date(l['created_at'] as String?)} · ${asInt(l['delta']) >= 0 ? '+' : ''}${l['delta']} (${l['reason']}) → ${l['balance_after']}',
                  ],
                ),
                _ListSection(
                  title: 'Journal',
                  rows: [
                    for (final a in asList(u['audit']))
                      '${_date(a['created_at'] as String?)} · ${a['action']}'
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({required this.title, required this.rows});

  final String title;
  final List<String> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(rows.isEmpty ? 'Aucun.' : rows.join('\n'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.6)),
            ),
          ),
        ],
      );
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer')),
        ],
      ),
    ) ??
    false;

Future<(int, String)?> _creditsDialog(BuildContext context) async {
  final delta = TextEditingController();
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Ajuster les crédits'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: delta,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration:
              const InputDecoration(labelText: 'Variation (ex. 10 ou -5)'),
        ),
        const SizedBox(height: 8),
        TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Motif (journalisé)')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Valider')),
      ],
    ),
  );
  final value = int.tryParse(delta.text.trim());
  final r = reason.text.trim();
  delta.dispose();
  reason.dispose();
  if (ok != true || value == null || value == 0 || r.isEmpty) return null;
  return (value, r);
}

Future<(String, int, String)?> _subscriptionDialog(
    BuildContext context, List<String> plans) async {
  if (plans.isEmpty) return null;
  var plan = plans.first;
  var months = 1;
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Offrir un abonnement'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: plan,
            items: [
              for (final p in plans)
                DropdownMenuItem(value: p, child: Text(p.replaceAll('_', ' ')))
            ],
            onChanged: (v) => setState(() => plan = v ?? plan),
            decoration: const InputDecoration(labelText: 'Forfait'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: months,
            items: [
              for (final m in [1, 3, 6, 12])
                DropdownMenuItem(value: m, child: Text('$m mois'))
            ],
            onChanged: (v) => setState(() => months = v ?? months),
            decoration: const InputDecoration(labelText: 'Durée'),
          ),
          const SizedBox(height: 8),
          TextField(
              controller: reason,
              decoration:
                  const InputDecoration(labelText: 'Motif (journalisé)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Accorder')),
        ],
      ),
    ),
  );
  final r = reason.text.trim();
  reason.dispose();
  if (ok != true || r.isEmpty) return null;
  return (plan, months, r);
}

/// Accès à la fiche depuis un identifiant (utilisé par le journal).
void openAdminUser(BuildContext context, String id) =>
    context.push(AppRoutes.adminUserFor(id));

/// Message générique en cas d'erreur de chargement.
String adminLoadError(Object e) => userMessageFor(e);
