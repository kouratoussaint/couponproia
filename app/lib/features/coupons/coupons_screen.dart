import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../matches/presentation/sports_widgets.dart';
import '../shell/app_drawer.dart';
import '../system/system_providers.dart';
import 'data/coupon_models.dart';
import 'data/coupon_query.dart';
import 'data/coupon_repository.dart';
import 'presentation/coupon_actions.dart';
import 'presentation/coupon_query_bar.dart';
import 'presentation/coupon_widgets.dart';

/// Onglet Coupons : coupons publiés par la plateforme, triables et filtrables (catégorie, état,
/// risque, cote, période). Appui long : actions. Les coupons retirés restent visibles, grisés.
class CouponsScreen extends ConsumerStatefulWidget {
  const CouponsScreen({super.key});

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen>
    with AutomaticKeepAliveClientMixin {
  String? _category;
  CouponQuery _query = const CouponQuery();

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
                final (:open, :past) =
                    _query.apply(all, category: _category, now: now);
                final perms = ref.watch(myPermissionsProvider).valueOrNull ??
                    const <String>{};
                final withdrawn = past.where((c) => c.isWithdrawn).toList();
                Widget card(Coupon c) => CouponCard(
                      coupon: c,
                      onTap: () =>
                          context.push(AppRoutes.couponDetailFor(c.id)),
                      onLongPress: () => showCouponActions(context, ref, c),
                    );
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
                      if (all.isNotEmpty)
                        CouponQueryBar(
                          query: _query,
                          count: open.length + past.length,
                          onChanged: (q) => setState(() => _query = q),
                        ),
                      if (all.isEmpty)
                        const InfoMessage(
                          icon: Icons.receipt_long,
                          title: 'Aucun coupon publié pour l’instant',
                          body:
                              'Le moteur publie des coupons seulement quand des matchs à venir ont des cotes '
                              'récentes et que des sélections remplissent ses critères. Sinon, il s’abstient.',
                        )
                      else if (open.isEmpty && past.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            const Text('Aucun coupon pour ces filtres.'),
                            TextButton(
                              onPressed: () => setState(() {
                                _query = _query.cleared;
                                _category = null;
                              }),
                              child: const Text('Effacer les filtres'),
                            ),
                          ]),
                        ),
                      if (open.isNotEmpty)
                        const SectionTitle('En cours et à venir'),
                      for (final c in open) card(c),
                      if (past.isNotEmpty)
                        const SectionTitle('Historique, pertes comprises'),
                      if (withdrawn.isNotEmpty &&
                          perms.contains('coupons.publish'))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.error),
                            onPressed: () =>
                                deleteWithdrawnCoupons(context, ref, withdrawn),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(withdrawn.length == 1
                                ? 'Supprimer le coupon retiré affiché'
                                : 'Supprimer les ${withdrawn.length} coupons retirés affichés'),
                          ),
                        ),
                      for (final c in past) card(c),
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
