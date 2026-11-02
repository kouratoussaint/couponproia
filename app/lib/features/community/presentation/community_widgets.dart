import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

class TipsterAvatar extends ConsumerWidget {
  const TipsterAvatar({super.key, required this.profile, this.radius = 20});

  final TipsterProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url =
        ref.watch(communityRepositoryProvider).avatarUrl(profile.avatarPath);
    final initials = profile.displayName.trim().isEmpty
        ? '?'
        : profile.displayName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w[0])
            .join()
            .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Text(initials,
          style: TextStyle(
              fontSize: radius * 0.75,
              fontWeight: FontWeight.w800,
              color: scheme.primary)),
    );
  }
}

/// Résultat d'un coupon publié (couleurs de la charte : vert gagné, rouge perdu).
class PostResultBadge extends StatelessWidget {
  const PostResultBadge({super.key, required this.result, this.odd});

  final String? result;
  final double? odd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (result) {
      'won' => (
          trf('Gagné{0}', [odd != null ? ' · ${decimal(odd!)}' : '']),
          BrandColors.vertIA
        ),
      'lost' => (tr('Perdu'), BrandColors.rouge),
      'void' => (tr('Annulé'), scheme.onSurfaceVariant),
      _ => (tr('En cours'), BrandColors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _CouponBlock extends StatelessWidget {
  const _CouponBlock({required this.coupon});

  final PostCoupon coupon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(trTitle(coupon.title),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700))),
              PostResultBadge(result: coupon.result, odd: coupon.settledOdd),
            ],
          ),
          const SizedBox(height: 8),
          for (final s in coupon.selections)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    switch (s.result) {
                      'won' => Icons.check_circle,
                      'lost' => Icons.cancel,
                      'void' => Icons.remove_circle_outline,
                      _ => Icons.schedule,
                    },
                    size: 18,
                    color: switch (s.result) {
                      'won' => BrandColors.vertIA,
                      'lost' => BrandColors.rouge,
                      _ => scheme.onSurfaceVariant,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s.match.home} – ${s.match.away}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium),
                        Text(
                          '${s.pickLabel} · ${shortDate(s.match.kickoffAt)} ${timeLabel(s.match.kickoffAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(decimal(s.odd),
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const Divider(height: 14),
          Row(
            children: [
              Text(trf('Cote {0}', [decimal(coupon.totalOdd)]),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    trf('Estimation du modèle {0}',
                        [pct(coupon.combinedProbability)]),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Publication dans un fil (texte ou coupon publié).
class PostCard extends ConsumerWidget {
  const PostCard(
      {super.key, required this.post, this.onChanged, this.openOnTap = true});

  final Post post;
  final VoidCallback? onChanged;
  final bool openOnTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            openOnTap ? () => context.push(AppRoutes.postFor(post.id)) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () =>
                        context.push(AppRoutes.tipsterFor(post.author.userId)),
                    borderRadius: BorderRadius.circular(24),
                    child: TipsterAvatar(profile: post.author),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => context
                          .push(AppRoutes.tipsterFor(post.author.userId)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post.author.displayName,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                              '@${post.author.handle} · ${relativeTime(post.createdAt, now)}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  PostMenu(post: post, onChanged: onChanged),
                ],
              ),
              if (post.hidden)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Text(
                      tr('Masquée par la modération : visible par vous seul.'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: BrandColors.orange)),
                ),
              if ((post.body ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: Text(post.body!, style: theme.textTheme.bodyMedium),
                ),
              if (post.coupon != null)
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CouponBlock(coupon: post.coupon!)),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await ref
                            .read(communityRepositoryProvider)
                            .setReaction(post.id, !post.myReaction);
                        onChanged?.call();
                      } catch (e) {
                        if (context.mounted) {
                          showMessage(context, communityErrorMessage(e),
                              error: true);
                        }
                      }
                    },
                    icon: Icon(
                        post.myReaction
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                        size: 18),
                    label: Text('${post.reactions}'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push(AppRoutes.postFor(post.id)),
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: Text('${post.comments}'),
                  ),
                  const Spacer(),
                  if (post.isCoupon && post.coupon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(tr('Publié avant le coup d’envoi'),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostMenu extends ConsumerWidget {
  const PostMenu({super.key, required this.post, this.onChanged});

  final Post post;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: tr('Options'),
      onSelected: (action) async {
        final repo = ref.read(communityRepositoryProvider);
        try {
          switch (action) {
            case 'report':
              await showReportSheet(context, ref, 'post', '${post.id}');
            case 'block':
              if (await confirmBlock(context, post.author.displayName)) {
                await repo.block(post.author.userId);
                if (context.mounted) {
                  showMessage(context,
                      trf('{0} est bloqué.', [post.author.displayName]));
                }
                onChanged?.call();
              }
            case 'delete':
              await repo.deletePost(post.id);
              if (context.mounted) {
                showMessage(context, tr('Publication supprimée.'));
              }
              onChanged?.call();
          }
        } catch (e) {
          if (context.mounted) {
            showMessage(context, communityErrorMessage(e), error: true);
          }
        }
      },
      itemBuilder: (_) => [
        if (post.isMine && !post.isCoupon)
          PopupMenuItem(value: 'delete', child: Text(tr('Supprimer'))),
        if (!post.isMine)
          PopupMenuItem(value: 'report', child: Text(tr('Signaler'))),
        if (!post.isMine)
          PopupMenuItem(
              value: 'block',
              child: Text(trf('Bloquer {0}', [post.author.displayName]))),
        if (post.isMine && post.isCoupon)
          PopupMenuItem(
              enabled: false,
              child:
                  Text(tr('Un coupon publié reste visible, pertes comprises'))),
      ],
    );
  }
}

Future<bool> confirmBlock(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(trf('Bloquer {0} ?', [name])),
        content: Text(tr(
            'Vous ne verrez plus ses publications ni ses commentaires, et il ne pourra plus commenter les vôtres. Vous pourrez le débloquer depuis votre profil.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Bloquer'))),
        ],
      ),
    ) ??
    false;

Future<void> showReportSheet(
    BuildContext context, WidgetRef ref, String type, String id) async {
  var reason = 'spam';
  final details = TextEditingController();
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Signaler'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: reason,
              onChanged: (v) => setState(() => reason = v ?? reason),
              child: Column(
                children: [
                  for (final e in reportReasons.entries)
                    RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: e.key,
                        title: Text(e.value)),
                ],
              ),
            ),
            TextField(
              controller: details,
              maxLength: 500,
              maxLines: 2,
              decoration:
                  InputDecoration(labelText: tr('Précisions (facultatif)')),
            ),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('Envoyer le signalement'))),
          ],
        ),
      ),
    ),
  );
  if (sent != true) return;
  try {
    await ref
        .read(communityRepositoryProvider)
        .report(type, id, reason, details.text);
    if (context.mounted) {
      showMessage(context,
          tr('Merci : l’équipe de modération va examiner ce signalement.'));
    }
  } catch (e) {
    if (context.mounted) {
      showMessage(context, communityErrorMessage(e), error: true);
    }
  } finally {
    details.dispose();
  }
}

/// Statistiques vérifiées, calculées par la plateforme.
class TipsterStatsCard extends StatelessWidget {
  const TipsterStatsCard({super.key, required this.stats});

  final TipsterStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tile(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        );
    Widget block(String title, TipsterNumbers n) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(children: [
              tile(tr('publiés'), '${n.published}'),
              tile(tr('gagnés'), '${n.won}'),
              tile(tr('perdus'), '${n.lost}'),
              tile(tr('en cours'), '${n.pending}'),
            ]),
            const SizedBox(height: 8),
            Text(
              stats.rateShown(n)
                  ? [
                      trf('Réussite {0} sur {1} coupons réglés',
                          [pct(n.winRate ?? 0), n.settled]),
                      if (n.averageOdd != null)
                        trf('cote moyenne {0}', [decimal(n.averageOdd!)]),
                      if (n.theoreticalReturn != null)
                        trf('rendement {0}{1}', [
                          n.theoreticalReturn! >= 0 ? '+' : '',
                          pct(n.theoreticalReturn!)
                        ]),
                    ].join(' · ')
                  : trf(
                      'Taux de réussite affiché à partir de {0} coupons réglés ({1} pour l’instant).',
                      [stats.minSettledForRate, n.settled]),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr('Statistiques vérifiées'),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800))),
              ],
            ),
            const SizedBox(height: 4),
            Text(stats.scope,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            block(tr('30 derniers jours'), stats.last30Days),
            const Divider(height: 28),
            block(tr('Depuis le début'), stats.allTime),
            if (stats.allTime.lastResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in stats.allTime.lastResults)
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (r == 'won'
                                ? BrandColors.vertIA
                                : r == 'lost'
                                    ? BrandColors.rouge
                                    : scheme.outline)
                            .withValues(alpha: 0.18),
                      ),
                      child: Text(
                          r == 'won'
                              ? 'G'
                              : r == 'lost'
                                  ? 'P'
                                  : 'A',
                          style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: r == 'won'
                                  ? BrandColors.vertIA
                                  : r == 'lost'
                                      ? BrandColors.rouge
                                      : scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
                trf('{0}. Les résultats passés ne garantissent pas les résultats futurs.',
                    [stats.stakeNote]),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Résumé d'un coupon publié par le Tipster lui-même (utilisé dans « Mon coupon »).
class PublishedBadge extends StatelessWidget {
  const PublishedBadge({super.key, required this.publishedAt});

  final DateTime publishedAt;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(Icons.public,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              trf('Publié sur votre profil Tipster le {0} à {1} : il ne peut plus être modifié ni supprimé.',
                  [shortDate(publishedAt), timeLabel(publishedAt)]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
}
