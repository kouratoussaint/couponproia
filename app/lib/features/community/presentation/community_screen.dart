import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/community_repository.dart';
import 'community_widgets.dart';

/// Communauté : fil des Tipsters suivis, découverte, annuaire des Tipsters.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rights = ref.watch(communityRightsProvider).valueOrNull;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communauté'),
          actions: [
            if (rights?.canModerate ?? false)
              IconButton(
                tooltip: 'Modération',
                onPressed: () => context.push(AppRoutes.moderation),
                icon: Badge(
                  isLabelVisible: (rights?.openReports ?? 0) > 0,
                  label: Text('${rights?.openReports ?? 0}'),
                  child: const Icon(Icons.shield_outlined),
                ),
              ),
            IconButton(
              tooltip: 'Mon profil Tipster',
              onPressed: () => context.push(AppRoutes.myTipsterProfile),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Abonnements'),
            Tab(text: 'Découvrir'),
            Tab(text: 'Tipsters'),
          ]),
        ),
        floatingActionButton: (rights?.isTipster ?? false)
            ? FloatingActionButton.extended(
                onPressed: () => showComposer(context, ref),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Publier'),
              )
            : null,
        body: rights != null && !rights.communityEnabled
            ? const InfoMessage(
                icon: Icons.construction,
                title: 'Communauté momentanément indisponible')
            : const TabBarView(children: [
                _Feed(scope: 'following'),
                _Feed(scope: 'all'),
                _Directory(),
              ]),
      ),
    );
  }
}

Future<void> showComposer(BuildContext context, WidgetRef ref) async {
  final text = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nouvelle publication', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Pour publier un coupon, ouvre-le dans « Mes coupons » puis « Publier ». '
            'Pas de promesse de résultat : « sûr », « garanti », « gain »… sont refusés.',
            style: Theme.of(c).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            autofocus: true,
            maxLength: 1000,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
                hintText: 'Ton analyse, ton avis sur la journée…'),
          ),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Publier')),
        ],
      ),
    ),
  );
  if (ok == true && text.text.trim().isNotEmpty) {
    try {
      await ref.read(communityRepositoryProvider).createTextPost(text.text);
      ref.invalidate(feedProvider);
      if (context.mounted) showMessage(context, 'Publié.');
    } catch (e) {
      if (context.mounted) {
        showMessage(context, communityErrorMessage(e), error: true);
      }
    }
  }
  text.dispose();
}

class _Feed extends ConsumerWidget {
  const _Feed({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider(scope));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(feedProvider(scope));
        ref.invalidate(communityRightsProvider);
        await ref.read(feedProvider(scope).future);
      },
      child: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          InfoMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Indisponible',
              body: userMessageFor(e))
        ]),
        data: (posts) => posts.isEmpty
            ? ListView(children: [
                InfoMessage(
                  icon: scope == 'following'
                      ? Icons.people_outline
                      : Icons.forum_outlined,
                  title: scope == 'following'
                      ? 'Aucune publication de tes Tipsters'
                      : 'Aucune publication pour l’instant',
                  body: scope == 'following'
                      ? 'Suis des Tipsters depuis l’onglet « Tipsters » : leurs coupons et analyses apparaîtront ici.'
                      : 'Les coupons publiés par les Tipsters apparaîtront ici, avec leurs résultats réels.',
                ),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  for (final p in posts)
                    PostCard(
                        post: p,
                        onChanged: () => ref.invalidate(feedProvider(scope))),
                ],
              ),
      ),
    );
  }
}

class _Directory extends ConsumerStatefulWidget {
  const _Directory();

  @override
  ConsumerState<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends ConsumerState<_Directory> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(directoryProvider(_query));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(directoryProvider(_query));
        await ref.read(directoryProvider(_query).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un Tipster'),
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 6),
          Text(
              'Classés par nombre de coupons réglés sur 30 jours (résultats vérifiés par la plateforme).',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ...list.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(userMessageFor(e))],
            data: (all) => all.isEmpty
                ? [
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun Tipster pour l’instant.'))
                  ]
                : [
                    for (final t in all)
                      Card(
                        child: ListTile(
                          leading: TipsterAvatar(profile: t.profile),
                          title: Text(t.profile.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            '@${t.profile.handle} · ${t.followers} abonné${t.followers > 1 ? 's' : ''}',
                            t.settled30d == 0
                                ? 'aucun coupon réglé sur 30 jours'
                                : '${t.settled30d} réglé${t.settled30d > 1 ? 's' : ''} sur 30 j'
                                    '${t.stats30d.winRate != null && t.settled30d >= 10 ? ' · réussite ${pct(t.stats30d.winRate!)}' : ''}',
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: t.iFollow
                              ? const Icon(Icons.check_circle_outline)
                              : const Icon(Icons.chevron_right),
                          onTap: () => context
                              .push(AppRoutes.tipsterFor(t.profile.userId)),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
