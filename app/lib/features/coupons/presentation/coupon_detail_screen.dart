import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/coupon_models.dart';
import '../data/coupon_repository.dart';
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
          title:
              Text(categoryLabels[coupon.valueOrNull?.category] ?? 'Coupon')),
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
    final canManage =
        (ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{})
            .contains('generation.manage');

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
        for (final s in c.selections)
          SelectionCard(
              selection: s, currentOdd: current['${s.match.id}:${s.key}']),
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
                for (final h in c.history)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(statusLabels[h.toStatus] ?? h.toStatus),
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
            onPressed: () => _withdraw(context, ref),
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Retirer ce coupon (administrateur)'),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          [
            'Moteur ${c.engineVersion}',
            'source ${c.dataSource}',
            if (c.summaryFromAi && c.aiModel != null)
              'analyse rédigée par l’IA (${c.aiModel}) et vérifiée',
            if (c.publishedAt != null)
              'publié le ${shortDate(c.publishedAt!)}/${c.publishedAt!.year} à ${timeLabel(c.publishedAt!)}',
          ].join(' · '),
          style: muted,
          textAlign: TextAlign.center,
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

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer le coupon'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: 'Motif (affiché aux utilisateurs)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(couponRepositoryProvider).withdraw(coupon.id, reason);
      ref.invalidate(couponProvider(coupon.id));
      ref.invalidate(publishedCouponsProvider);
      if (context.mounted) showMessage(context, 'Coupon retiré.');
    } catch (e) {
      if (context.mounted) showMessage(context, userMessageFor(e), error: true);
    }
  }
}
