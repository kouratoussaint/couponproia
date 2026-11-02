import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../shell/app_drawer.dart';
import '../../system/system_providers.dart';
import '../data/sports_format.dart';
import '../data/sports_repository.dart';
import '../../analysis/presentation/analyze_access.dart';
import '../../search/search_screen.dart';
import 'competitions_screen.dart';
import 'sports_widgets.dart';
import '../data/live_updates.dart';

/// Matchs : onglet Calendrier (un jour à la fois, hier à J+6, recherche et filtre par
/// compétition) et onglet Compétitions et classements.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key, this.initialTab = 0});

  /// 0 Calendrier, 1 Compétitions et classements (`/matchs?onglet=competitions`).
  final int initialTab;

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  DateTime? _day;
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
    final today = dateOnly(DateTime.now());
    final archive = ref.watch(archiveSeasonProvider).valueOrNull;
    final base = archive == null ? today : archiveDay(today, archive);
    final day = _day ?? base;
    final appBar = AppBar(
      leading: const DrawerMenuButton(),
      title: const Text('Matchs'),
      actions: [
        const SearchButton(),
        IconButton(
          tooltip: 'Choisir une date',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: day,
              firstDate: DateTime(2022, 7, 1),
              lastDate: DateTime(now.year + 1, 12, 31),
              helpText: 'Afficher les matchs du',
            );
            if (picked != null) {
              setState(() {
                _day = dateOnly(picked);
                _competitionId = null;
              });
            }
          },
        ),
      ],
      bottom: const TabBar(
        tabs: [
          Tab(text: 'Calendrier'),
          Tab(text: 'Compétitions et classements'),
        ],
      ),
    );

    if (flags != null && flags['matches'] == false) {
      return Scaffold(
        appBar: AppBar(
            leading: const DrawerMenuButton(), title: const Text('Matchs')),
        body: const InfoMessage(
          icon: Icons.sports_soccer,
          title: 'Matchs momentanément indisponibles',
          body:
              'Ce module est mis en pause pour le moment. Réessayez plus tard.',
        ),
      );
    }

    final days = [
      for (var i = -1; i <= 6; i++) DateTime(day.year, day.month, day.day + i)
    ];
    final matches = ref.watch(liveMatchesOfDayProvider(day));
    final markets =
        ref.watch(market1x2OfDayProvider(day)).valueOrNull ?? const {};

    final calendar = Column(
      children: [
        if (archive != null)
          MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: const Icon(Icons.history_edu_outlined),
            content: Text(
              'Données d’archive : saison ${seasonLabel(archive)}. Ce sont de vrais matchs, déjà joués ; '
              'la saison en cours sera disponible avec l’offre Pro du fournisseur.',
            ),
            actions: [
              TextButton(
                onPressed: () => setState(() {
                  _day = null;
                  _competitionId = null;
                }),
                child: const Text('Revenir au jour'),
              ),
            ],
          ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ChoiceChip(
              label: Text(dayLabel(days[i], today)),
              selected: days[i] == day,
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
              ref.invalidate(matchesOfDayProvider(day));
              ref.invalidate(market1x2OfDayProvider(day));
              await ref.read(matchesOfDayProvider(day).future);
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
                      onPressed: () =>
                          ref.invalidate(matchesOfDayProvider(day)),
                      child: const Text('Réessayer'),
                    ),
                  ),
                ],
              ),
              data: (all) {
                final groups = groupByCompetition(all);
                final filtered = all
                    .where((m) =>
                        _competitionId == null ||
                        m.competition.id == _competitionId)
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
                                onSelected: (_) =>
                                    setState(() => _competitionId = null),
                              ),
                            ),
                            for (final (competition, list) in groups)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  avatar: SportsLogo(
                                      url: competition.logoUrl, size: 18),
                                  label: Text(
                                      '${competition.name} (${list.length})'),
                                  selected: _competitionId == competition.id,
                                  onSelected: (_) => setState(
                                      () => _competitionId = competition.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (markets.isNotEmpty) const OneXTwoLegend(),
                    if (all.isEmpty)
                      const InfoMessage(
                        icon: Icons.event_busy_outlined,
                        title: 'Aucun match pour ce jour',
                        body:
                            'Aucune des compétitions suivies ne joue ce jour-là, ou le calendrier n’est pas encore '
                            'synchronisé (mise à jour chaque matin à 4 h). Essayez un autre jour.',
                      )
                    else if (filtered.isEmpty)
                      const InfoMessage(
                        icon: Icons.search_off,
                        title: 'Aucun match ne correspond à votre recherche',
                      ),
                    for (final (competition, list) in shown) ...[
                      _CompetitionHeader(
                          name: competition.name,
                          country: competition.country,
                          logoUrl: competition.logoUrl),
                      Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              MatchCard(
                                  match: list[i],
                                  market: markets[list[i].id],
                                  action: AnalyzeMatchButton(match: list[i])),
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
    );

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: appBar,
        body: TabBarView(
          children: [calendar, const CompetitionsList()],
        ),
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
          SportsLogo(
              url: logoUrl, size: 20, fallback: Icons.emoji_events_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
          if (country != null)
            Text(country!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
