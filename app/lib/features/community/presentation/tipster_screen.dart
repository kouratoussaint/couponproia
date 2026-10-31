import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/community_repository.dart';
import 'community_widgets.dart';

/// Profil public d'un Tipster : présentation, statistiques vérifiées, publications.
class TipsterScreen extends ConsumerWidget {
  const TipsterScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(tipsterProvider(userId));
    final stats = ref.watch(tipsterStatsProvider(userId));
    final posts = ref.watch(tipsterFeedProvider(userId));
    final following =
        ref.watch(isFollowingProvider(userId)).valueOrNull ?? false;
    final me = ref.watch(currentUserProvider)?.id;
    final isMe = me == userId;

    Future<void> refresh() async {
      ref.invalidate(tipsterProvider(userId));
      ref.invalidate(tipsterStatsProvider(userId));
      ref.invalidate(tipsterFeedProvider(userId));
      ref.invalidate(isFollowingProvider(userId));
      await ref.read(tipsterStatsProvider(userId).future);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tipster'),
        actions: [
          if (isMe)
            IconButton(
              tooltip: 'Modifier',
              onPressed: () => context.push(AppRoutes.myTipsterProfile),
              icon: const Icon(Icons.edit_outlined),
            )
          else if (profile.valueOrNull != null)
            PopupMenuButton<String>(
              onSelected: (a) async {
                final p = profile.valueOrNull!;
                if (a == 'report') {
                  await showReportSheet(context, ref, 'tipster', userId);
                } else if (a == 'block' &&
                    await confirmBlock(context, p.displayName)) {
                  try {
                    await ref.read(communityRepositoryProvider).block(userId);
                    ref.invalidate(feedProvider);
                    if (context.mounted) {
                      showMessage(context, '${p.displayName} est bloqué.');
                      context.pop();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showMessage(context, communityErrorMessage(e),
                          error: true);
                    }
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Signaler')),
                PopupMenuItem(value: 'block', child: Text('Bloquer')),
              ],
            ),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
            body: userMessageFor(e)),
        data: (p) => p == null
            ? const InfoMessage(
                icon: Icons.person_off_outlined, title: 'Tipster introuvable')
            : RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                TipsterAvatar(profile: p, radius: 32),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p.displayName,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w800)),
                                      Text('@${p.handle}',
                                          style: theme.textTheme.bodyMedium),
                                      if (stats.valueOrNull != null)
                                        Text(
                                            '${stats.valueOrNull!.followers} abonné${stats.valueOrNull!.followers > 1 ? 's' : ''}',
                                            style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if ((p.bio ?? '').isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(p.bio!, style: theme.textTheme.bodyMedium),
                            ],
                            if (!p.isActive) ...[
                              const SizedBox(height: 8),
                              Text('Profil suspendu par la modération.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error)),
                            ],
                            if (!isMe) ...[
                              const SizedBox(height: 14),
                              following
                                  ? OutlinedButton.icon(
                                      onPressed: () =>
                                          _follow(context, ref, false),
                                      icon: const Icon(Icons.check),
                                      label: const Text('Abonné'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: () =>
                                          _follow(context, ref, true),
                                      icon: const Icon(Icons.person_add_alt_1),
                                      label: const Text('Suivre'),
                                    ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    stats.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text(userMessageFor(e)),
                      data: (s) => TipsterStatsCard(stats: s),
                    ),
                    const SectionTitle('Publications'),
                    ...posts.when(
                      loading: () => [const LinearProgressIndicator()],
                      error: (e, _) => [Text(userMessageFor(e))],
                      data: (list) => list.isEmpty
                          ? [
                              const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                      'Aucune publication pour l’instant.'))
                            ]
                          : [
                              for (final post in list)
                                PostCard(
                                    post: post,
                                    onChanged: () => ref.invalidate(
                                        tipsterFeedProvider(userId))),
                            ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _follow(BuildContext context, WidgetRef ref, bool on) async {
    try {
      await ref.read(communityRepositoryProvider).setFollowing(userId, on);
      ref.invalidate(isFollowingProvider(userId));
      ref.invalidate(tipsterStatsProvider(userId));
      ref.invalidate(feedProvider);
      ref.invalidate(directoryProvider);
    } catch (e) {
      if (context.mounted) {
        showMessage(context, communityErrorMessage(e), error: true);
      }
    }
  }
}
