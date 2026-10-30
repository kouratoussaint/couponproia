import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../matches/presentation/sports_widgets.dart';
import '../shell/app_drawer.dart';
import '../system/system_providers.dart';
import 'data/coupon_models.dart';
import 'data/coupon_repository.dart';
import 'presentation/coupon_widgets.dart';

/// Onglet Coupons : coupons publiés par la plateforme, filtrables par catégorie.
class CouponsScreen extends ConsumerStatefulWidget {
  const CouponsScreen({super.key});

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen>
    with AutomaticKeepAliveClientMixin {
  String? _category;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final flags =
        ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};
    final coupons = ref.watch(publishedCouponsProvider);

    Future<void> refresh() async {
      ref.invalidate(publishedCouponsProvider);
      await ref.read(publishedCouponsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Coupons'),
        actions: [
          IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: refresh)
        ],
      ),
      body: flags['platform_coupons'] == false
          ? const InfoMessage(
              icon: Icons.pause_circle_outline,
              title: 'Coupons momentanément indisponibles')
          : coupons.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Coupons indisponibles',
                body: userMessageFor(e),
                action: FilledButton(
                    onPressed: refresh, child: const Text('Réessayer')),
              ),
              data: (all) {
                final now = DateTime.now();
                final categories = {for (final c in all) c.category}.toList()
                  ..sort((a, b) => categoryLabels.keys
                      .toList()
                      .indexOf(a)
                      .compareTo(categoryLabels.keys.toList().indexOf(b)));
                final list = _category == null
                    ? all
                    : all.where((c) => c.category == _category).toList();
                final open = list.where((c) => c.isOpen(now)).toList()
                  ..sort(
                      (a, b) => a.firstKickoffAt.compareTo(b.firstKickoffAt));
                final past = list.where((c) => !c.isOpen(now)).toList();
                return RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                    children: [
                      if (categories.length > 1)
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('Tous'),
                                  selected: _category == null,
                                  onSelected: (_) =>
                                      setState(() => _category = null),
                                ),
                              ),
                              for (final cat in categories)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(categoryLabels[cat] ?? cat),
                                    selected: _category == cat,
                                    onSelected: (_) => setState(() =>
                                        _category =
                                            _category == cat ? null : cat),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (all.isEmpty)
                        const InfoMessage(
                          icon: Icons.receipt_long,
                          title: 'Aucun coupon publié pour l’instant',
                          body:
                              'Le moteur publie des coupons seulement quand des matchs à venir ont des cotes '
                              'récentes et que des sélections remplissent ses critères. Sinon, il s’abstient.',
                        ),
                      if (open.isNotEmpty)
                        const SectionTitle('En cours et à venir'),
                      for (final c in open)
                        CouponCard(
                            coupon: c,
                            onTap: () =>
                                context.push(AppRoutes.couponDetailFor(c.id))),
                      if (past.isNotEmpty) const SectionTitle('Précédents'),
                      for (final c in past)
                        CouponCard(
                            coupon: c,
                            onTap: () =>
                                context.push(AppRoutes.couponDetailFor(c.id))),
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Coupons composés par le moteur statistique de la plateforme, contrôlés avant publication. '
                          'Les probabilités sont des estimations : aucun gain n’est garanti. Pariez de façon responsable.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
