import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/form_widgets.dart';
import '../assistant/data/assistant_repository.dart';
import '../assistant/presentation/my_coupons_screen.dart';
import '../community/data/community_repository.dart';
import '../coupons/data/coupon_repository.dart';
import '../coupons/presentation/coupon_tiles.dart';
import '../matches/data/live_updates.dart';
import '../matches/data/sports_models.dart';
import '../matches/data/sports_repository.dart';
import '../matches/presentation/sports_widgets.dart';
import 'search_repository.dart';

/// Recherche : équipes (à suivre), compétitions (classement), matchs des 3 derniers jours
/// aux 10 prochains, coupons de la plateforme et vos coupons.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300),
        () => mounted ? setState(() => _query = v.trim()) : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query;
    final teams = searchTeams(
        ref.watch(allTeamsProvider).valueOrNull ?? const <TeamRef>[], q);
    final competitions = searchCompetitions(
        ref.watch(competitionsProvider).valueOrNull ?? const [], q);
    final coupons = searchable(q)
        ? searchCoupons(
            ref.watch(activeCouponsProvider).valueOrNull ?? const [], q)
        : const [];
    final mine = searchable(q)
        ? searchMyCoupons(
            ref.watch(savedCouponsProvider).valueOrNull ?? const [], q)
        : const [];
    final ids = ([for (final t in teams) t.id]..sort()).join(',');
    final live = ref.watch(liveUpdatesProvider);
    final matches = ref
        .watch(teamMatchesProvider(ids))
        .whenData((list) => [for (final m in list) withLive(m, live[m.id])]);
    final favorites =
        ref.watch(favoriteTeamsProvider).valueOrNull ?? const <int, String>{};
    final loadingTeams = ref.watch(allTeamsProvider).isLoading;

    Widget section(String title, int count) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text('$title · $count',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        );

    final nothing = searchable(q) &&
        !loadingTeams &&
        teams.isEmpty &&
        competitions.isEmpty &&
        coupons.isEmpty &&
        mine.isEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: 'Équipe, compétition, coupon…',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _controller.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        children: [
          if (!searchable(q))
            const InfoMessage(
              icon: Icons.search,
              title: 'Que cherchez-vous ?',
              body:
                  'Tapez au moins 2 lettres : une équipe, une compétition ou un pays. '
                  'Les accents et majuscules ne comptent pas.',
            ),
          if (nothing)
            const InfoMessage(
              icon: Icons.search_off,
              title: 'Aucun résultat',
              body: 'Vérifiez l’orthographe ou essayez une partie du nom.',
            ),
          if (teams.isNotEmpty) ...[
            section('Équipes', teams.length),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final t in teams)
                  ListTile(
                    leading: SportsLogo(url: t.logoUrl, size: 28),
                    title: Text(t.name),
                    trailing: IconButton(
                      tooltip: favorites.containsKey(t.id)
                          ? 'Ne plus suivre'
                          : 'Suivre cette équipe',
                      icon: Icon(
                          favorites.containsKey(t.id)
                              ? Icons.star
                              : Icons.star_outline,
                          color: favorites.containsKey(t.id)
                              ? theme.colorScheme.primary
                              : null),
                      onPressed: () async {
                        try {
                          await ref
                              .read(communityRepositoryProvider)
                              .setFavoriteTeam(
                                  t.id, !favorites.containsKey(t.id));
                          ref.invalidate(favoriteTeamsProvider);
                        } catch (e) {
                          if (context.mounted) {
                            showMessage(context, userMessageFor(e),
                                error: true);
                          }
                        }
                      },
                    ),
                  ),
              ]),
            ),
          ],
          if (teams.isNotEmpty)
            ...matches.when(
              loading: () => [
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator())
              ],
              error: (e, _) => [Text(userMessageFor(e))],
              data: (list) => list.isEmpty
                  ? const <Widget>[]
                  : [
                      section('Matchs (3 derniers jours, 10 prochains)',
                          list.length),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            MatchCard(match: list[i]),
                          ],
                        ]),
                      ),
                    ],
            ),
          if (competitions.isNotEmpty) ...[
            section('Compétitions', competitions.length),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final c in competitions)
                  ListTile(
                    leading: SportsLogo(
                        url: c.logoUrl,
                        size: 28,
                        fallback: Icons.emoji_events_outlined),
                    title: Text(c.name),
                    subtitle: c.country == null ? null : Text(c.country!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.standingsFor(c.id)),
                  ),
              ]),
            ),
          ],
          if (coupons.isNotEmpty) ...[
            section('Coupons IA', coupons.length),
            for (final c in coupons)
              CompactCouponTile(
                  coupon: c,
                  onTap: () => context.push(AppRoutes.couponDetailFor(c.id))),
          ],
          if (mine.isNotEmpty) ...[
            section('Mes coupons', mine.length),
            for (final c in mine) MyCouponTile(coupon: c),
          ],
        ],
      ),
    );
  }
}

/// Bouton loupe des barres d'application.
class SearchButton extends StatelessWidget {
  const SearchButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Rechercher',
        icon: const Icon(Icons.search),
        onPressed: () => context.push(AppRoutes.search),
      );
}
