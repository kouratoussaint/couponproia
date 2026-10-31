import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../community/data/community_models.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/notifications_repository.dart';
import '../data/push_service.dart';

const _kindIcons = {
  'coupon': Icons.receipt_long_outlined,
  'result': Icons.emoji_events_outlined,
  'tipster': Icons.forum_outlined,
  'match': Icons.sports_soccer_outlined,
  'morning': Icons.wb_sunny_outlined,
  'credits': Icons.bolt,
  'system': Icons.info_outline,
};

/// Cloche avec le nombre de notifications non lues.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push(AppRoutes.notifications),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

/// Boîte de réception : toutes les notifications, même sans notifications sur le téléphone.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(inboxProvider);
    ref.invalidate(unreadCountProvider);
    await ref.read(inboxProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inbox = ref.watch(inboxProvider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Tout marquer comme lu',
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markRead();
              await _refresh(ref);
            },
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: 'Réglages',
            onPressed: () => context.push(AppRoutes.notificationSettings),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: inbox.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Indisponible',
                body: userMessageFor(e))
          ]),
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  InfoMessage(
                    icon: Icons.notifications_none,
                    title: 'Aucune notification',
                    body:
                        'Coupons publiés, résultats de vos coupons, publications des Tipsters suivis et '
                        'rappels de match apparaîtront ici.',
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    for (final n in list)
                      Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child:
                              Icon(Icons.delete_outline, color: scheme.error),
                        ),
                        onDismissed: (_) async {
                          await ref
                              .read(notificationsRepositoryProvider)
                              .delete(n.id);
                          ref.invalidate(unreadCountProvider);
                        },
                        child: Card(
                          color: n.isRead
                              ? null
                              : scheme.primaryContainer.withValues(alpha: 0.45),
                          child: ListTile(
                            leading: Icon(
                                _kindIcons[n.kind] ?? Icons.notifications_none,
                                color: scheme.primary),
                            title: Text(n.title,
                                style: TextStyle(
                                    fontWeight: n.isRead
                                        ? FontWeight.w500
                                        : FontWeight.w800)),
                            subtitle: Text(
                                '${n.body}\n${relativeTime(n.createdAt, now)}'),
                            isThreeLine: true,
                            onTap: () async {
                              if (!n.isRead) {
                                await ref
                                    .read(notificationsRepositoryProvider)
                                    .markRead([n.id]);
                                ref.invalidate(inboxProvider);
                                ref.invalidate(unreadCountProvider);
                              }
                              if (n.route != null && context.mounted) {
                                context.push(n.route!);
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Réglages des notifications.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefs = ref.watch(notificationPrefsProvider);
    final push = ref.watch(pushServiceProvider);
    final pushBlocked = !push.available
        ? 'Cet appareil ne peut pas recevoir les notifications de Coupon Pro IA. '
        : push.permissionDenied
            ? 'Les notifications sont bloquées dans les réglages du téléphone. '
            : null;

    Future<void> set(Map<String, Object> values) async {
      try {
        await ref.read(notificationsRepositoryProvider).updatePrefs(values);
        ref.invalidate(notificationPrefsProvider);
      } catch (e) {
        if (context.mounted) {
          showMessage(context, userMessageFor(e), error: true);
        }
      }
    }

    String hour(int h) => '${h.toString().padLeft(2, '0')}:00';

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages des notifications')),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
            body: userMessageFor(e)),
        data: (p) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            if (pushBlocked != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Notifications dans l’app'),
                  subtitle:
                      Text('${pushBlocked}Elles restent visibles ici, dans la '
                          'boîte de réception (cloche de l’accueil).'),
                ),
              ),
            Card(
              child: SwitchListTile(
                title: const Text('Notifications sur le téléphone'),
                subtitle: const Text(
                    'Coupe toutes les alertes du téléphone ; la boîte de réception continue de se remplir.'),
                value: p.enabled,
                onChanged: (v) => set({'notifications_enabled': v}),
              ),
            ),
            const SectionTitle('Ce que je reçois'),
            Card(
              child: Column(
                children: [
                  for (final (column, title, desc) in notificationKinds)
                    SwitchListTile(
                      title: Text(title),
                      subtitle: Text(desc),
                      value: switch (column) {
                        'notify_coupons' => p.coupons,
                        'notify_results' => p.results,
                        'notify_tipsters' => p.tipsters,
                        'notify_matches' => p.matches,
                        'notify_morning' => p.morning,
                        _ => p.credits,
                      },
                      onChanged: (v) => set({column: v}),
                    ),
                ],
              ),
            ),
            const SectionTitle('Heures calmes'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Aucune notification sur le téléphone pendant cette plage : elles arrivent à la fin.'),
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        DropdownButton<int>(
                          value: p.quietStart,
                          items: [
                            for (var h = 0; h < 24; h++)
                              DropdownMenuItem(value: h, child: Text(hour(h)))
                          ],
                          onChanged: (v) =>
                              v == null ? null : set({'quiet_start': v}),
                        ),
                        const Text('→'),
                        DropdownButton<int>(
                          value: p.quietEnd,
                          items: [
                            for (var h = 0; h < 24; h++)
                              DropdownMenuItem(value: h, child: Text(hour(h)))
                          ],
                          onChanged: (v) =>
                              v == null ? null : set({'quiet_end': v}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.hasQuietHours
                          ? 'Silence de ${hour(p.quietStart)} à ${hour(p.quietEnd)} (heure de votre profil).'
                          : 'Pas d’heures calmes.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
