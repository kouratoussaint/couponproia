import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../analysis/data/analysis_format.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../coupons/data/coupon_models.dart';
import '../../coupons/data/coupon_repository.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/studio_repository.dart';

/// Studio graphique : choisir un coupon à mettre en forme.
class StudioHomeScreen extends ConsumerWidget {
  const StudioHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rights = ref.watch(studioRightsProvider).valueOrNull;
    final platform = ref.watch(publishedCouponsProvider);
    final mine = ref.watch(savedCouponsProvider);
    final remaining = rights?.remaining;
    return Scaffold(
      appBar: AppBar(title: const Text('Studio graphique')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(studioRightsProvider);
          ref.invalidate(publishedCouponsProvider);
          ref.invalidate(savedCouponsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Card(
              child: ListTile(
                leading: Icon(Icons.palette_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Transformez un coupon en visuel'),
                subtitle: Text([
                  'Carré, portrait, story ou paysage ; PNG, JPG ou PDF.',
                  if (rights != null && remaining != null)
                    '$remaining visuel(s) restant(s) aujourd’hui.',
                ].join(' ')),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Mon identité visuelle'),
                subtitle:
                    const Text('Nom, couleurs, logo, couverture, signature'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.studioBranding),
              ),
            ),
            const SectionTitle('Coupons de la plateforme'),
            platform.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) {
                final usable = list
                    .where((c) =>
                        !c.isWithdrawn && !c.locked && c.selections.isNotEmpty)
                    .take(20)
                    .toList();
                if (usable.isEmpty) {
                  return const Text('Aucun coupon disponible pour le moment.');
                }
                return Card(
                  child: Column(children: [
                    for (final c in usable)
                      _CouponTile(
                        title: c.title,
                        subtitle:
                            '${categoryLabels[c.category] ?? c.category} · ${c.selections.length} sélection(s) · '
                            '${shortDate(c.firstKickoffAt)} ${timeLabel(c.firstKickoffAt)}',
                        odd: c.totalOdd,
                        onTap: () =>
                            context.push(AppRoutes.studioFor('platform', c.id)),
                      ),
                  ]),
                );
              },
            ),
            const SectionTitle('Mes coupons enregistrés'),
            mine.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) {
                final usable = list
                    .where((c) => c.selections.isNotEmpty)
                    .take(20)
                    .toList();
                if (usable.isEmpty) {
                  return const Text(
                      'Aucun coupon enregistré. Créez-en un avec l’assistant ou le laboratoire.');
                }
                return Card(
                  child: Column(children: [
                    for (final c in usable)
                      _CouponTile(
                        title: c.title,
                        subtitle:
                            '${c.selections.length} sélection(s) · créé le ${shortDate(c.createdAt)}',
                        odd: c.totalOdd,
                        onTap: () =>
                            context.push(AppRoutes.studioFor('user', c.id)),
                      ),
                  ]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile(
      {required this.title,
      required this.subtitle,
      required this.odd,
      required this.onTap});

  final String title;
  final String subtitle;
  final double odd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text('Cote ${decimal(odd)}',
            style: Theme.of(context).textTheme.labelLarge),
        onTap: onTap,
      );
}
