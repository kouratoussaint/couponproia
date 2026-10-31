import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../matches/data/sports_format.dart';
import '../matches/presentation/sports_widgets.dart';
import '../shell/app_drawer.dart';
import '../system/system_providers.dart';
import 'data/coupon_models.dart';
import 'data/coupon_phase.dart';
import 'data/coupon_repository.dart';
import 'presentation/coupon_actions.dart';
import 'presentation/coupon_tiles.dart';
import 'presentation/coupon_widgets.dart';

/// Onglet Coupons, en trois onglets :
/// - « À jouer » : aucun match commencé (Coupon du jour en avant, puis lignes compactes) ;
/// - « En cours » : au moins un match commencé, rien de décidé (progression, scores) ;
/// - « Résultats » : coupons décidés, groupés par jour avec leur bilan, pertes comprises ;
///   les coupons retirés sont repliés en bas, grisés.
/// Un coupon passe dans « Résultats » dès que le serveur l'a décidé.
/// Onglet demandé depuis un autre écran (0 À jouer, 1 En cours, 2 Résultats), lu une fois.
final couponsTabRequestProvider = StateProvider<int?>((ref) => null);

class CouponsScreen extends ConsumerStatefulWidget {
  const CouponsScreen({super.key});

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen>
    with AutomaticKeepAliveClientMixin {
  int? _tab;
  String? _category;
  ToPlaySort _sort = ToPlaySort.kickoff;
  ResultKind _kind = ResultKind.all;
  int _days = 7;
  int _limit = decidedPageSize;

  @override
  bool get wantKeepAlive => true;

  void _open(Coupon c) => context.push(AppRoutes.couponDetailFor(c.id));

  void _actions(Coupon c) => showCouponActions(context, ref, c);

  Future<void> _refresh() async {
    invalidateCouponLists(ref);
    await ref.read(activeCouponsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final flags =
        ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};
    final requested = ref.watch(couponsTabRequestProvider);
    if (requested != null) {
      _tab = requested;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(couponsTabRequestProvider.notifier).state = null;
      });
    }
    final active = ref.watch(activeCouponsProvider);
    final decided = ref.watch(decidedCouponsProvider(_limit));
    final withdrawn = ref.watch(withdrawnCouponsProvider);
    final now = DateTime.now();

    final split = splitActive(active.valueOrNull ?? const [], now,
        category: _category, sort: _sort);
    final inPeriod = filterDecided(decided.valueOrNull ?? const [], now,
        category: _category, days: _days);
    final shown = inPeriod.where(_kind.accepts).toList();
    final tab = _tab ??
        (!active.hasValue
            ? 0
            : split.toPlay.isNotEmpty
                ? 0
                : split.live.isNotEmpty
                    ? 1
                    : 2);
    final categories = {
      for (final c in [
        ...?active.valueOrNull,
        ...?decided.valueOrNull,
      ])
        c.category
    }.toList()
      ..sort((a, b) => categoryLabels.keys
          .toList()
          .indexOf(a)
          .compareTo(categoryLabels.keys.toList().indexOf(b)));

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Coupons'),
        actions: [
          IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh)
        ],
      ),
      body: flags['platform_coupons'] == false
          ? const InfoMessage(
              icon: Icons.pause_circle_outline,
              title: 'Coupons momentanément indisponibles')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: CouponTabs(
                    selected: tab,
                    labels: [
                      'À jouer · ${active.hasValue ? split.toPlay.length : '…'}',
                      'En cours · ${active.hasValue ? split.live.length : '…'}',
                      'Résultats · ${decided.hasValue ? inPeriod.length : '…'}',
                    ],
                    onSelected: (i) => setState(() => _tab = i),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                      children: switch (tab) {
                        0 => _toPlay(active, split.toPlay, categories, now),
                        1 => _live(active, split.live, now),
                        _ => _results(
                            decided, inPeriod, shown, withdrawn, categories),
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _loadState(AsyncValue<List<Coupon>> v) => [
        if (v.isLoading && !v.hasValue)
          const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator())),
        if (v.hasError && !v.hasValue)
          InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Coupons indisponibles',
            body: userMessageFor(v.error!),
            action: FilledButton(
                onPressed: _refresh, child: const Text('Réessayer')),
          ),
      ];

  // '' = tous les types (une valeur nulle serait prise pour une annulation du menu).
  Widget _typeMenu(List<String> categories) => _PillMenu<String>(
        label: _category == null
            ? 'Tous les types'
            : categoryLabels[_category] ?? _category!,
        value: _category ?? '',
        items: {
          '': 'Tous les types',
          for (final c in categories) c: categoryLabels[c] ?? c,
        },
        onSelected: (v) => setState(() => _category = v.isEmpty ? null : v),
      );

  List<Widget> _toPlay(AsyncValue<List<Coupon>> active, List<Coupon> list,
      List<String> categories, DateTime now) {
    final theme = Theme.of(context);
    final featured = list.where((c) => c.category == 'du_jour').firstOrNull;
    final rest = [
      for (final c in list)
        if (c != featured) c
    ];
    final out = <Widget>[
      Wrap(spacing: 8, runSpacing: 8, children: [
        _typeMenu(categories),
        _PillMenu<ToPlaySort>(
          label: _sort.label,
          value: _sort,
          items: {for (final s in ToPlaySort.values) s: s.label},
          onSelected: (v) => setState(() => _sort = v),
        ),
      ]),
      ..._loadState(active),
    ];
    if (active.hasValue && list.isEmpty) {
      out.add(InfoMessage(
        icon: Icons.event_available_outlined,
        title: 'Aucun coupon à jouer pour l’instant',
        body:
            'Le moteur publie des coupons quand des matchs à venir ont des cotes récentes et que des '
            'sélections remplissent ses critères. Sinon, il s’abstient.',
        action: TextButton(
            onPressed: () => setState(() => _tab = 2),
            child: const Text('Voir les résultats')),
      ));
      return out;
    }
    DateTime? lastDay;
    Widget? dayHeader(Coupon c) {
      if (_sort != ToPlaySort.kickoff) return null;
      final d = dateOnly(c.firstKickoffAt);
      if (d == lastDay) return null;
      lastDay = d;
      final label = dayLabel(d, now);
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
        child: Text(
            (label.contains('/') ? label : '$label · ${shortDate(d)}')
                .toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      );
    }

    // Le Coupon du jour reste en tête, hors des intertitres de jour.
    if (featured != null) {
      out.add(const SizedBox(height: 6));
      out.add(FeaturedCouponCard(
          coupon: featured,
          onTap: () => _open(featured),
          onLongPress: () => _actions(featured)));
    }
    for (final c in rest) {
      final h = dayHeader(c);
      if (h != null) out.add(h);
      out.add(CompactCouponTile(
          coupon: c, onTap: () => _open(c), onLongPress: () => _actions(c)));
    }
    out.add(_footer(
        'Probabilités estimées par le modèle, jamais des certitudes. Appui long sur un coupon : '
        'partager, copier, créer un visuel.'));
    return out;
  }

  List<Widget> _live(
      AsyncValue<List<Coupon>> active, List<Coupon> list, DateTime now) {
    final theme = Theme.of(context);
    final next = [
      for (final c in list)
        for (final s in c.selections)
          if (selectionState(s) == SelectionState.pending) s.match.kickoffAt
    ]..sort();
    return [
      ..._loadState(active),
      if (active.hasValue && list.isEmpty)
        const InfoMessage(
          icon: Icons.sports_soccer_outlined,
          title: 'Aucun coupon en cours',
          body: 'Un coupon arrive ici au coup d’envoi de son premier match.',
        ),
      if (next.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: Text(
              'PROCHAIN MATCH ${kickoffShort(next.first, now).toUpperCase()}',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4)),
        ),
      for (final c in list)
        LiveCouponCard(
            coupon: c, onTap: () => _open(c), onLongPress: () => _actions(c)),
      if (active.hasValue)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _tab = 2),
            child: const Text('Les coupons déjà décidés sont dans Résultats'),
          ),
        ),
    ];
  }

  List<Widget> _results(
      AsyncValue<List<Coupon>> decided,
      List<Coupon> inPeriod,
      List<Coupon> shown,
      AsyncValue<List<Coupon>> withdrawn,
      List<String> categories) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final kinds = [
      ResultKind.all,
      ResultKind.won,
      ResultKind.lost,
      if (inPeriod.any((c) => c.result == 'void')) ResultKind.voided,
    ];
    final retired = [
      for (final c in withdrawn.valueOrNull ?? const <Coupon>[])
        if (_category == null || c.category == _category) c
    ];
    final mayHaveMore = (decided.valueOrNull?.length ?? 0) >= _limit;
    return [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final k in kinds)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _PillMenu<int>(
          label: resultPeriods[_days]!,
          value: _days,
          items: resultPeriods,
          onSelected: (v) => setState(() => _days = v),
        ),
        _typeMenu(categories),
      ]),
      ..._loadState(decided),
      if (decided.hasValue && shown.isEmpty)
        InfoMessage(
          icon: Icons.history,
          title: 'Aucun résultat pour ces critères',
          body: _days == 0
              ? null
              : 'Les coupons plus anciens restent consultables avec la période « Tout ».',
          action: _days == 0
              ? null
              : TextButton(
                  onPressed: () => setState(() => _days = 0),
                  child: const Text('Tout afficher')),
        ),
      for (final day in groupByDay(shown)) ...[
        ResultDayHeader(day),
        for (final c in day.coupons)
          ResultCouponTile(
              coupon: c, onTap: () => _open(c), onLongPress: () => _actions(c)),
      ],
      if (decided.hasValue && mayHaveMore)
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() {
              _limit += decidedPageSize;
              _days = 0;
            }),
            icon: const Icon(Icons.expand_more),
            label: const Text('Charger les jours précédents'),
          ),
        ),
      if (decided.hasValue && !mayHaveMore && _days != 0 && shown.isNotEmpty)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _days = 0),
            child: const Text('Voir tout l’historique'),
          ),
        ),
      if (retired.isNotEmpty)
        Card(
          margin: const EdgeInsets.only(top: 12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.block),
            title: Text('Coupons retirés (${retired.length})'),
            subtitle: const Text('Retirés par l’équipe, hors statistiques'),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              if (perms.contains('coupons.publish'))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () =>
                        deleteWithdrawnCoupons(context, ref, retired),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(retired.length == 1
                        ? 'Supprimer définitivement'
                        : 'Supprimer définitivement les ${retired.length}'),
                  ),
                ),
              for (final c in retired)
                CouponCard(
                    coupon: c,
                    onTap: () => _open(c),
                    onLongPress: () => _actions(c)),
            ],
          ),
        ),
      if (decided.hasValue)
        _footer(
            'Tous les coupons publiés restent consultables, gagnés comme perdus. Bilan détaillé : '
            'menu → Performances.'),
    ];
  }

  Widget _footer(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      child: Text(text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Bouton-pilule ouvrant un menu de choix (type, tri, période).
class _PillMenu<T extends Object> extends StatelessWidget {
  const _PillMenu(
      {required this.label,
      required this.value,
      required this.items,
      required this.onSelected});

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final e in items.entries)
          CheckedPopupMenuItem<T>(
              value: e.key, checked: e.key == value, child: Text(e.value)),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}
