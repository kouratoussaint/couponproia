import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../coupons/data/coupon_models.dart';
import '../../coupons/presentation/coupon_tiles.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../community/data/community_models.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/notifications_repository.dart';
import '../data/push_service.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

const _kindIcons = {
  'coupon': Icons.receipt_long_outlined,
  'result': Icons.emoji_events_outlined,
  'tipster': Icons.forum_outlined,
  'match': Icons.sports_soccer_outlined,
  'morning': Icons.wb_sunny_outlined,
  'credits': Icons.bolt,
  'odds': Icons.trending_down,
  'budget': Icons.shield_outlined,
  'analysis': Icons.query_stats,
  'reminder': Icons.alarm,
  'live': Icons.sports_soccer,
  'billing': Icons.workspace_premium_outlined,
  'news': Icons.campaign_outlined,
  'system': Icons.info_outline,
};

/// Cloche avec le nombre de notifications non lues.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: tr('Notifications'),
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
        title: Text(tr('Notifications')),
        actions: [
          IconButton(
            tooltip: tr('Tout marquer comme lu'),
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markRead();
              await _refresh(ref);
            },
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: tr('Réglages'),
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
                title: tr('Indisponible'),
                body: userMessageFor(e))
          ]),
          data: (list) => list.isEmpty
              ? ListView(children: [
                  InfoMessage(
                    icon: Icons.notifications_none,
                    title: tr('Aucune notification'),
                    body: tr(
                        'Coupons publiés, résultats de vos coupons, publications des Tipsters suivis et rappels de match apparaîtront ici.'),
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
        ? tr(
            'Cet appareil ne peut pas recevoir les notifications de Coupon Pro IA. ')
        : push.permissionDenied
            ? tr(
                'Les notifications sont bloquées dans les réglages du téléphone. ')
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
      appBar: AppBar(title: Text(tr('Réglages des notifications'))),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Indisponible'),
            body: userMessageFor(e)),
        data: (p) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            if (pushBlocked != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(tr('Notifications dans l’app')),
                  subtitle: Text(trf(
                      '{0}Elles restent visibles ici, dans la boîte de réception (cloche de l’accueil).',
                      [pushBlocked])),
                ),
              ),
            Card(
              child: SwitchListTile(
                title: Text(tr('Notifications sur le téléphone')),
                subtitle: Text(tr(
                    'Coupe toutes les alertes du téléphone ; la boîte de réception continue de se remplir.')),
                value: p.enabled,
                onChanged: (v) => set({'notifications_enabled': v}),
              ),
            ),
            SectionTitle(tr('Ce que je reçois')),
            Card(
              child: Column(
                children: [
                  for (final (column, title, desc) in notificationKinds)
                    SwitchListTile(
                      title: Text(title),
                      subtitle: Text(desc),
                      value: prefValue(p, column),
                      onChanged: (v) => set({column: v}),
                    ),
                ],
              ),
            ),
            SectionTitle(tr('Par e-mail')),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.mail_outline),
                title: Text(tr('Rapport hebdomadaire par e-mail')),
                subtitle: Text(trf(
                    'Le lundi matin : votre bilan de la semaine (Mes coupons, carnet de paris) et celui des coupons de la plateforme, pertes comprises.{0}',
                    [
                      ref.watch(currentUserProvider)?.email == null
                          ? ''
                          : trf(' Envoyé à {0}.',
                              [ref.watch(currentUserProvider)!.email])
                    ])),
                value: p.weeklyEmail,
                onChanged: (v) => set({'weekly_email': v}),
              ),
            ),
            if (p.coupons) ...[
              SectionTitle(tr('Types de coupons notifiés')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          p.couponCategories.isEmpty
                              ? tr(
                                  'Tous les types que votre forfait permet de lire.')
                              : tr('Seulement les types choisis.'),
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          FilterChip(
                            label: Text(tr('Tous')),
                            selected: p.couponCategories.isEmpty,
                            onSelected: (_) =>
                                set({'coupon_categories': <String>[]}),
                          ),
                          for (final MapEntry(key: code, value: label)
                              in categoryLabels.entries)
                            FilterChip(
                              avatar: Icon(categoryIcon(code), size: 16),
                              label: Text(label),
                              selected: p.couponCategories.contains(code),
                              onSelected: (on) {
                                final next = {...p.couponCategories};
                                on ? next.add(code) : next.remove(code);
                                set({
                                  'coupon_categories': next.toList()..sort()
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SectionTitle(tr('Heures calmes')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(
                        'Aucune notification sur le téléphone pendant cette plage : elles arrivent à la fin. Exceptions : scores en direct, rappels de vos paris et alertes de budget, utiles sur le moment.')),
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
                          ? trf('Silence de {0} à {1} (heure de votre profil).',
                              [hour(p.quietStart), hour(p.quietEnd)])
                          : tr('Pas d’heures calmes.'),
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
