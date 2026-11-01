import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/super_admin_note.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/coupon_models.dart';
import '../data/coupon_repository.dart';
import '../../simulator/presentation/sim_entries.dart';
import '../data/coupon_watch.dart';
import 'bookmaker_actions.dart';
import 'coupon_actions.dart';
import 'coupon_widgets.dart';

/// Fiche d'un coupon : sélections avec cote publiée (conservée) et cote actuelle,
/// justification de chaque pronostic, analyse générale, fiabilité, source, historique.
class CouponDetailScreen extends ConsumerWidget {
  const CouponDetailScreen({super.key, required this.couponId});

  final String couponId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupon = ref.watch(couponProvider(couponId));
    return Scaffold(
      appBar: AppBar(
        title: Text(categoryLabels[coupon.valueOrNull?.category] ?? 'Coupon'),
        actions: [
          if (coupon.valueOrNull case final c?
              when c.status == 'published' &&
                  !c.locked &&
                  c.firstKickoffAt.isAfter(DateTime.now()))
            _WatchButton(couponId: c.id),
          if (coupon.valueOrNull case final c?
              when !c.locked && !c.isWithdrawn && c.selections.isNotEmpty)
            IconButton(
              tooltip: 'Créer un visuel',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () =>
                  context.push(AppRoutes.studioFor('platform', c.id)),
            ),
        ],
      ),
      body: coupon.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Coupon indisponible',
            body: userMessageFor(e)),
        data: (c) => c == null
            ? const InfoMessage(
                icon: Icons.help_outline, title: 'Coupon introuvable')
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(couponProvider(couponId));
                  await ref.read(couponProvider(couponId).future);
                },
                child: _CouponBody(coupon: c),
              ),
      ),
    );
  }
}

class _CouponBody extends ConsumerWidget {
  const _CouponBody({required this.coupon});

  final Coupon coupon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = coupon;
    final current = ref.watch(currentOddsProvider(c.id)).valueOrNull ??
        const <String, double>{};
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final canManage = perms.contains('generation.manage');
    final canDelete = perms.contains('coupons.publish');

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        if (c.isWithdrawn)
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Coupon retiré par la plateforme${c.statusNote == null ? '' : ' : ${c.statusNote}'}. '
                'Son contenu d’origine reste affiché pour la transparence.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        if (c.result != null)
          Card(
            child: ListTile(
              leading: ResultBadge(result: c.result, odd: c.settledOdd),
              title: Text(c.result == 'won'
                  ? 'Coupon gagnant${c.settledOdd != null && c.settledOdd != c.totalOdd ? ' (cote réglée ${decimal(c.settledOdd!)} après annulation d’une sélection)' : ''}'
                  : c.result == 'lost'
                      ? 'Coupon perdant'
                      : 'Coupon annulé (toutes les sélections annulées)'),
              subtitle: c.settledAt == null
                  ? null
                  : Text(
                      'Réglé le ${shortDate(c.settledAt!)} à ${timeLabel(c.settledAt!)}, sur le score à 90 minutes'),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child:
                            Text(c.title, style: theme.textTheme.titleLarge)),
                  ],
                ),
                if (c.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(c.description, style: muted),
                ],
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cote totale', style: theme.textTheme.labelMedium),
                        Text(decimal(c.totalOdd),
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: theme.colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Probabilité estimée (modèle)',
                              style: theme.textTheme.labelMedium),
                          Text(pct(c.combinedProbability),
                              style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    RiskBadge(risk: c.riskLevel),
                    if (!c.locked)
                      Text('${c.selections.length} sélections',
                          style: theme.textTheme.labelMedium),
                  ],
                ),
                if (c.marketNote != null) ...[
                  const SizedBox(height: 8),
                  Text(c.marketNote!, style: muted),
                ],
              ],
            ),
          ),
        ),
        const SectionTitle('Sélections'),
        if (c.locked) LockedCouponNotice(firstKickoffAt: c.firstKickoffAt),
        if (!c.locked && c.result == null)
          _OddsMoveBanner(coupon: c, current: current),
        for (final s in c.selections)
          SelectionCard(
              selection: s, currentOdd: current['${s.match.id}:${s.key}']),
        if (!c.locked && !c.isWithdrawn && c.selections.isNotEmpty) ...[
          const SizedBox(height: 8),
          SimulateButton(choices: () => [couponSim(c, current)], filled: true),
          const SizedBox(height: 8),
          BookmakerButtons(
              title: c.title, totalOdd: c.totalOdd, selections: c.selections),
        ],
        if (c.summary.isNotEmpty) ...[
          const SectionTitle('Analyse générale'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(c.summary, style: theme.textTheme.bodyMedium),
                  if (c.vigilance.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Points de vigilance',
                        style: theme.textTheme.labelLarge),
                    for (final v in c.vigilance)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(
                                child:
                                    Text(v, style: theme.textTheme.bodySmall))
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (c.history.isNotEmpty) ...[
          const SectionTitle('Historique'),
          Card(
            child: Column(
              children: [
                // Action la plus récente en premier.
                for (final (i, h) in c.history.reversed.indexed)
                  ListTile(
                    dense: true,
                    leading: _HistoryIcon(h.toStatus, latest: i == 0),
                    title: Text(statusLabels[h.toStatus] ?? h.toStatus,
                        style: i == 0
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null),
                    subtitle: Text(
                      '${shortDate(h.at)}/${h.at.year} à ${timeLabel(h.at)}${h.reason == null ? '' : ' · ${h.reason}'}',
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (canManage && c.status == 'published') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => withdrawCoupon(context, ref, c),
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Retirer ce coupon (administrateur)'),
          ),
        ],
        if (canDelete && c.isWithdrawn) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error),
            onPressed: () async {
              if (await deleteWithdrawnCoupons(context, ref, [c]) &&
                  context.mounted) {
                context.pop();
              }
            },
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Supprimer définitivement (administrateur)'),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          [
            if (c.summaryFromAi)
              'Analyse rédigée par l’IA à partir de données vérifiées',
            if (c.publishedAt != null)
              'publié le ${shortDate(c.publishedAt!)}/${c.publishedAt!.year} à ${timeLabel(c.publishedAt!)}',
          ].join(' · '),
          style: muted,
          textAlign: TextAlign.center,
        ),
        if (perms.contains('ai.providers'))
          SuperAdminNote(
            text: [
              'moteur ${c.engineVersion}',
              'source ${c.dataSource}',
              if (c.aiModel != null) 'IA ${c.aiModel}',
            ].join(' · '),
          ),
        const SizedBox(height: 4),
        Text(
          'Probabilité combinée = produit des probabilités du modèle, matchs supposés indépendants. '
          'Les cotes publiées sont conservées ; la cote actuelle est affichée à part. '
          'Ce sont des estimations : aucun gain n’est garanti. Pariez de façon responsable.',
          style: muted,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Icône d'une étape de l'historique ; la plus récente est mise en couleur.
class _HistoryIcon extends StatelessWidget {
  const _HistoryIcon(this.status, {required this.latest});

  final String status;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      'published' => (Icons.campaign_outlined, scheme.primary),
      'ready' => (Icons.event_available_outlined, scheme.primary),
      'pending_review' => (Icons.rate_review_outlined, scheme.tertiary),
      'rejected' || 'withdrawn' => (Icons.block, scheme.error),
      'expired' => (Icons.timer_off_outlined, scheme.outline),
      _ => (Icons.history, scheme.onSurfaceVariant),
    };
    final c = latest ? color : scheme.onSurfaceVariant;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
          color: c.withValues(alpha: latest ? 0.16 : 0.08),
          shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: c),
    );
  }
}

/// Cloche « Suivre la cote » : alerte si une cote bouge fortement avant le match.
class _WatchButton extends ConsumerWidget {
  const _WatchButton({required this.couponId});

  final String couponId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(couponWatchedProvider(couponId)).valueOrNull;
    if (watched == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: watched ? 'Ne plus suivre la cote' : 'Suivre la cote',
      icon: Icon(watched
          ? Icons.notifications_active
          : Icons.notifications_none_outlined),
      onPressed: () async {
        try {
          final on = await setCouponWatch(ref, couponId, !watched);
          if (context.mounted) {
            showMessage(
                context,
                on
                    ? 'Vous serez prévenu si une cote bouge fortement avant le match.'
                    : 'Vous ne suivez plus la cote de ce coupon.');
          }
        } catch (e) {
          if (context.mounted) {
            showMessage(context, userMessageFor(e), error: true);
          }
        }
      },
    );
  }
}

/// Bandeau quand la cote totale a bougé d'au moins le seuil réglé depuis la publication.
class _OddsMoveBanner extends ConsumerWidget {
  const _OddsMoveBanner({required this.coupon, required this.current});

  final Coupon coupon;
  final Map<String, double> current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final move = totalOddsMove([
      for (final s in coupon.selections)
        (published: s.odd, current: current['${s.match.id}:${s.key}'])
    ]);
    final threshold =
        oddsMoveThreshold(ref.watch(publicSettingsProvider).valueOrNull);
    if (move == null || move.abs() < threshold) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final down = move < 0;
    final color = down ? scheme.error : BrandColors.orange;
    final now = coupon.totalOdd * (1 + move);
    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading:
            Icon(down ? Icons.trending_down : Icons.trending_up, color: color),
        title: Text(
            'Cote totale actuelle ${decimal(now)} (${down ? '−' : '+'}${(move.abs() * 100).round()} %)'),
        subtitle: Text(down
            ? 'Le marché y croit davantage depuis la publication : le retour potentiel diminue.'
            : 'Le marché y croit moins depuis la publication (absence, composition ?) : vérifiez avant de jouer.'),
      ),
    );
  }
}
