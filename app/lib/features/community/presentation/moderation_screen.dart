import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

final _targetLabels = {
  'post': tr('Publication'),
  'comment': tr('Commentaire'),
  'tipster': tr('Profil Tipster')
};

/// File des signalements (permission moderation.manage, vérifiée par le serveur).
class ModerationScreen extends ConsumerWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queue = ref.watch(moderationQueueProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Modération'))),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(moderationQueueProvider);
          await ref.read(moderationQueueProvider.future);
        },
        child: queue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            InfoMessage(
                icon: Icons.lock_outline,
                title: tr('Accès refusé'),
                body: userMessageFor(e))
          ]),
          data: (items) => items.isEmpty
              ? ListView(children: [
                  InfoMessage(
                      icon: Icons.task_alt,
                      title: tr('Aucun signalement en attente'))
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    for (final m in items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${_targetLabels[m.targetType] ?? m.targetType} · ${reportReasons[m.reason] ?? m.reason}'
                                '${m.reportsOnTarget > 1 ? trf(' · {0} signalements', [
                                        m.reportsOnTarget
                                      ]) : ''}',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(relativeTime(m.createdAt, DateTime.now()),
                                  style: theme.textTheme.bodySmall),
                              if ((m.details ?? '').isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(trf('Précisions : {0}', [m.details]),
                                    style: theme.textTheme.bodyMedium),
                              ],
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${m.previewAuthor ?? tr('Auteur inconnu')} : ${m.previewText ?? tr('(contenu supprimé)')}'
                                  '${m.previewStatus == 'hidden' || m.previewStatus == 'suspended' ? tr('\n(déjà masqué)') : ''}',
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _act(context, ref, m,
                                        m.targetType, m.targetId, 'dismiss'),
                                    child: Text(tr('Rejeter')),
                                  ),
                                  if (m.targetType != 'tipster')
                                    FilledButton.tonal(
                                      onPressed: () => _act(context, ref, m,
                                          m.targetType, m.targetId, 'hide'),
                                      child: Text(tr('Masquer')),
                                    ),
                                  if (m.targetType == 'post')
                                    TextButton(
                                      onPressed: () => context.push(
                                          AppRoutes.postFor(
                                              int.parse(m.targetId))),
                                      child: Text(tr('Voir')),
                                    ),
                                  if (m.previewAuthorId != null &&
                                      m.targetType != 'comment')
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor:
                                              theme.colorScheme.error),
                                      onPressed: () => _act(
                                          context,
                                          ref,
                                          m,
                                          'tipster',
                                          m.previewAuthorId!,
                                          'suspend'),
                                      child: Text(tr('Suspendre le Tipster')),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, ModerationItem m,
      String type, String id, String action) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(switch (action) {
          'dismiss' => tr('Rejeter le signalement ?'),
          'hide' => tr('Masquer ce contenu ?'),
          _ => tr('Suspendre ce Tipster ?'),
        }),
        content: TextField(
            controller: note,
            decoration: InputDecoration(labelText: tr('Motif (journalisé)'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Confirmer'))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(communityRepositoryProvider).moderate(type, id, action,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
            report: m.id);
        ref.invalidate(moderationQueueProvider);
        ref.invalidate(communityRightsProvider);
        ref.invalidate(feedProvider);
        if (context.mounted) showMessage(context, tr('Action enregistrée.'));
      } catch (e) {
        if (context.mounted) {
          showMessage(context, communityErrorMessage(e), error: true);
        }
      }
    }
    note.dispose();
  }
}

/// Utilisateurs bloqués, avec déblocage.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Utilisateurs bloqués'))),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Indisponible'),
            body: userMessageFor(e)),
        data: (users) => users.isEmpty
            ? InfoMessage(
                icon: Icons.block, title: tr('Aucun utilisateur bloqué'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final u in users)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.block),
                        title: Text(u.name),
                        trailing: TextButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(communityRepositoryProvider)
                                  .unblock(u.userId);
                              ref.invalidate(blockedUsersProvider);
                              ref.invalidate(feedProvider);
                            } catch (e) {
                              if (context.mounted) {
                                showMessage(context, communityErrorMessage(e),
                                    error: true);
                              }
                            }
                          },
                          child: Text(tr('Débloquer')),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Équipes suivies : leurs matchs passent en premier sur l'accueil.
class FavoriteTeamsScreen extends ConsumerWidget {
  const FavoriteTeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(favoriteTeamsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Équipes suivies'))),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Indisponible'),
            body: userMessageFor(e)),
        data: (map) => map.isEmpty
            ? InfoMessage(
                icon: Icons.star_border,
                title: tr('Aucune équipe suivie'),
                body: tr(
                    'Dans la fiche d’un match, touchez l’étoile à côté d’une équipe pour la suivre : ses matchs passeront en premier sur l’accueil.'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final e in map.entries)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.star),
                        title: Text(e.value),
                        trailing: TextButton(
                          onPressed: () async {
                            await ref
                                .read(communityRepositoryProvider)
                                .setFavoriteTeam(e.key, false);
                            ref.invalidate(favoriteTeamsProvider);
                          },
                          child: Text(tr('Ne plus suivre')),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
