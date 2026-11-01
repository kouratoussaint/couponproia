import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/super_admin_note.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/history_filter.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../coupons/data/coupon_models.dart';
import '../../coupons/presentation/bookmaker_actions.dart';
import '../../simulator/presentation/sim_entries.dart';
import '../../coupons/presentation/coupon_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_widgets.dart';
import '../../studio/data/studio_models.dart';
import '../data/assistant_models.dart';
import '../../system/system_providers.dart';
import '../data/assistant_repository.dart';

/// Mes coupons : coupons enregistrés depuis l'assistant ou le laboratoire.
class MyCouponsScreen extends ConsumerStatefulWidget {
  const MyCouponsScreen({super.key});

  @override
  ConsumerState<MyCouponsScreen> createState() => _MyCouponsScreenState();
}

class _MyCouponsScreenState extends ConsumerState<MyCouponsScreen> {
  HistoryFilter _filter = const HistoryFilter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coupons = ref.watch(savedCouponsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes coupons')),
      body: coupons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
            body: userMessageFor(e)),
        data: (list) => list.isEmpty
            ? const InfoMessage(
                icon: Icons.bookmarks_outlined,
                title: 'Aucun coupon enregistré',
                body: 'Demandez un coupon à l’assistant, puis « Enregistrer ».',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(savedCouponsProvider),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    HistoryFilterBar(
                        value: _filter,
                        onChanged: (v) => setState(() => _filter = v)),
                    const SizedBox(height: 8),
                    if (!list
                        .any((c) => _filter.accepts(c.result, c.createdAt)))
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun coupon pour ce filtre.'),
                      ),
                    for (final c in list)
                      if (_filter.accepts(c.result, c.createdAt))
                        Card(
                          child: ListTile(
                            onTap: () =>
                                context.push(AppRoutes.myCouponFor(c.id)),
                            title: Text(c.title),
                            subtitle: Text(
                              '${c.selections.map((s) => '${s.match.home} – ${s.match.away}').join(' · ')}\n'
                              'Créé le ${shortDate(c.createdAt)} · probabilité estimée ${pct(c.combinedProbability)}'
                              '${c.result == null ? '' : ' · ${resultLabels[c.result] ?? c.result}'}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: Text(decimal(c.totalOdd),
                                style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.primary)),
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Détail d'un coupon de l'utilisateur.
class MyCouponDetailScreen extends ConsumerWidget {
  const MyCouponDetailScreen({super.key, required this.couponId});

  final String couponId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coupon = ref.watch(userCouponProvider(couponId));
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon coupon'),
        actions: [
          if (coupon.valueOrNull case final c? when c.selections.isNotEmpty)
            IconButton(
              tooltip: 'Créer un visuel',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => context.push(AppRoutes.studioFor('user', c.id)),
            ),
        ],
      ),
      body: coupon.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
            body: userMessageFor(e)),
        data: (c) => c == null
            ? const InfoMessage(
                icon: Icons.help_outline, title: 'Coupon introuvable')
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('Cote totale ${decimal(c.totalOdd)}',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: theme.colorScheme.primary)),
                          Text(
                              'Probabilité estimée par le modèle : ${pct(c.combinedProbability)}'
                              '${c.impliedProbability == null ? '' : ' (marché : ${pct(c.impliedProbability!)})'}'),
                          const SizedBox(height: 8),
                          RiskBadge(risk: c.riskLevel),
                        ],
                      ),
                    ),
                  ),
                  for (final w in c.warnings)
                    Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text('⚠ $w', style: muted)),
                  const SectionTitle('Sélections'),
                  for (final s in c.selections) SelectionCard(selection: s),
                  if (c.summary.isNotEmpty) ...[
                    const SectionTitle('Analyse'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.summary),
                            for (final v in c.vigilance)
                              Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('• $v',
                                      style: theme.textTheme.bodySmall)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (c.isPublished) ...[
                    const SizedBox(height: 8),
                    PublishedBadge(publishedAt: c.publishedAt!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!c.isPublished && c.status != 'archived')
                        FilledButton.icon(
                          onPressed: () => _publish(context, ref, c.id),
                          icon: const Icon(Icons.public),
                          label: const Text('Publier sur mon profil Tipster'),
                        ),
                      if (!c.isSaved)
                        FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(assistantRepositoryProvider)
                                .setStatus(c.id, 'saved');
                            ref.invalidate(userCouponProvider(c.id));
                            ref.invalidate(savedCouponsProvider);
                          },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Enregistrer'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutes.labFor(c.id)),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Laboratoire'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                            text: couponShareText(
                                c.title,
                                c.totalOdd,
                                c.selections,
                                (s) => outcomeKeyLabel(
                                    s.key, s.match.home, s.match.away)),
                          ));
                          if (context.mounted) {
                            showMessage(context,
                                'Coupon copié : collez-le où vous voulez.');
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copier pour partager'),
                      ),
                      SimulateButton(choices: () => [userCouponSim(c)]),
                      FilledButton.tonalIcon(
                        onPressed: () => copyForBookmaker(
                            context, ref, c.title, c.totalOdd, c.selections),
                        icon: const Icon(Icons.content_paste_go_outlined),
                        label: const Text('Copier pour mon bookmaker'),
                      ),
                      if (!c.isPublished)
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(assistantRepositoryProvider)
                                  .deleteCoupon(c.id);
                              ref.invalidate(savedCouponsProvider);
                              if (context.mounted) context.pop();
                            } catch (e) {
                              if (context.mounted) {
                                showMessage(context, userMessageFor(e),
                                    error: true);
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Supprimer'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Créé le ${shortDate(c.createdAt)}/${c.createdAt.year} à ${timeLabel(c.createdAt)}. '
                    'Cotes relevées au moment de la création : elles ont pu changer. Estimations, sans garantie de gain.',
                    style: muted,
                    textAlign: TextAlign.center,
                  ),
                  if (ref
                          .watch(myPermissionsProvider)
                          .valueOrNull
                          ?.contains('ai.providers') ??
                      false)
                    SuperAdminNote(text: 'moteur ${c.engineVersion}'),
                ],
              ),
      ),
    );
  }
}

/// Publication sur le profil Tipster : définitive, avant le premier coup d'envoi.
Future<void> _publish(
    BuildContext context, WidgetRef ref, String couponId) async {
  final comment = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Publier ce coupon ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Il apparaîtra sur votre profil Tipster et dans le fil de vos abonnés. '
              'Une fois publié, il ne peut plus être modifié ni supprimé : son résultat comptera '
              'dans vos statistiques, qu’il soit gagné ou perdu.'),
          const SizedBox(height: 12),
          TextField(
            controller: comment,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
                labelText: 'Votre commentaire (facultatif)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Publier')),
      ],
    ),
  );
  if (ok == true) {
    final bad = forbiddenWordIn(comment.text);
    if (bad != null) {
      if (context.mounted) {
        showMessage(
            context, 'Texte refusé : « $bad ». Pas de promesse de résultat.',
            error: true);
      }
    } else {
      try {
        await ref
            .read(communityRepositoryProvider)
            .publishCoupon(couponId, comment.text);
        ref.invalidate(userCouponProvider(couponId));
        ref.invalidate(savedCouponsProvider);
        ref.invalidate(feedProvider);
        if (context.mounted) {
          showMessage(context, 'Coupon publié sur votre profil Tipster.');
        }
      } catch (e) {
        if (context.mounted) {
          showMessage(context, communityErrorMessage(e), error: true);
        }
      }
    }
  }
  comment.dispose();
}
