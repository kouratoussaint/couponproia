import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/coming_soon_view.dart';
import '../../shell/app_drawer.dart';
import '../../system/system_providers.dart';
import '../data/sports_format.dart';
import '../data/sports_repository.dart';
import 'sports_widgets.dart';

/// Calendrier des matchs : un jour à la fois (hier à J+6), recherche et filtre par compétition.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  late DateTime _day = dateOnly(DateTime.now());
  int? _competitionId;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(featureFlagsProvider).valueOrNull;
    final appBar = AppBar(
      leading: const DrawerMenuButton(),
      title: const Text('Matchs'),
      actions: [
        IconButton(
          tooltip: 'Compétitions et classements',
          icon: const Icon(Icons.emoji_events_outlined),
          onPressed: () => context.push(AppRoutes.competitions),
        ),
      ],
    );

    if (flags != null && flags['matches'] == false) {
      return Scaffold(
        appBar: appBar,
        body: const ComingSoonView(
          icon: Icons.sports_soccer,
          title: 'Matchs momentanément indisponibles',
          lot: 'LOT 2',
          description: 'L’administration a désactivé ce module. Réessayez plus tard.',
        ),
      );
    }

    final today = dateOnly(DateTime.now());
    final days = [for (var i = -1; i <= 6; i++) DateTime(today.year, today.month, today.day + i)];
    final matches = ref.watch(matchesOfDayProvider(_day));

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ChoiceChip(
                label: Text(dayLabel(days[i], today)),
                selected: days[i] == _day,
                onSelected: (_) => setState(() {
                  _day = days[i];
                  _competitionId = null;
                }),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Rechercher une équipe ou une compétition',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(matchesOfDayProvider(_day));
                await ref.read(matchesOfDayProvider(_day).future);
              },
              child: matches.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  children: [
                    InfoMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Impossible de charger les matchs',
                      body: userMessageFor(e),
                      action: OutlinedButton(
                        onPressed: () => ref.invalidate(matchesOfDayProvider(_day)),
                        child: const Text('Réessayer'),
                      ),
                    ),
                  ],
                ),
                data: (all) {
                  final groups = groupByCompetition(all);
                  final filtered = all
                      .where((m) => _competitionId == null || m.competition.id == _competitionId)
                      .where((m) => matchesQuery(m, _search.text))
                      .toList();
                  final shown = groupByCompetition(filtered);
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (groups.length > 1)
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: const Text('Toutes'),
                                  selected: _competitionId == null,
                                  onSelected: (_) => setState(() => _competitionId = null),
                                ),
                              ),
                              for (final (competition, list) in groups)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    avatar: SportsLogo(url: competition.logoUrl, size: 18),
                                    label: Text('${competition.name} (${list.length})'),
                                    selected: _competitionId == competition.id,
                                    onSelected: (_) => setState(() => _competitionId = competition.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (all.isEmpty)
                        const InfoMessage(
                          icon: Icons.event_busy_outlined,
                          title: 'Aucun match synchronisé pour ce jour',
                          body: 'Les calendriers des compétitions suivies sont mis à jour chaque matin à 4 h. '
                              'Tirez vers le bas pour actualiser.',
                        )
                      else if (filtered.isEmpty)
                        const InfoMessage(
                          icon: Icons.search_off,
                          title: 'Aucun match ne correspond à votre recherche',
                        ),
                      for (final (competition, list) in shown) ...[
                        _CompetitionHeader(name: competition.name, country: competition.country, logoUrl: competition.logoUrl),
                        Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < list.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                MatchCard(match: list[i]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompetitionHeader extends StatelessWidget {
  const _CompetitionHeader({required this.name, this.country, this.logoUrl});

  final String name;
  final String? country;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          SportsLogo(url: logoUrl, size: 20, fallback: Icons.emoji_events_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
          if (country != null)
            Text(country!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
