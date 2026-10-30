import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../coupons/data/coupon_models.dart';
import '../../coupons/presentation/coupon_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/assistant_models.dart';
import '../data/assistant_repository.dart';

/// Mes coupons : coupons enregistrés depuis l'assistant.
class MyCouponsScreen extends ConsumerWidget {
  const MyCouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    for (final c in list)
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
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: theme.colorScheme.primary)),
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
      appBar: AppBar(title: const Text('Mon coupon')),
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
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
                    'Moteur ${c.engineVersion} · créé le ${shortDate(c.createdAt)}/${c.createdAt.year} à ${timeLabel(c.createdAt)}. '
                    'Cotes relevées au moment de la création : elles ont pu changer. Estimations, sans garantie de gain.',
                    style: muted,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}
