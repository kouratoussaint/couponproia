import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/share_links.dart';
import '../../analysis/data/analysis_repository.dart';
import '../../lab/presentation/manual_coupon_bar.dart';
import '../data/insights_models.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'match_tabs.dart';
import 'sports_widgets.dart';
import '../../community/data/community_repository.dart';
import '../../../core/widgets/form_widgets.dart';

/// Fiche d'un match : en-tête, puis 4 onglets (Pronostic, Analyse, Marchés, Stats).
/// Les estimations viennent du moteur (serveur) ; chaque fait indique sa source et son heure.
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    return Scaffold(
      bottomNavigationBar: const ManualCouponBar(),
      appBar: AppBar(
        title: Text(match.valueOrNull?.competition.name ?? 'Match'),
        actions: [
          if (match.valueOrNull case final m?)
            IconButton(
              tooltip: 'Partager',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(ShareParams(
                  text: matchShareText(m, shareLink(ref, matchId: m.id)))),
            ),
        ],
      ),
      body: match.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Match indisponible',
            body: userMessageFor(e)),
        data: (m) => m == null
            ? const InfoMessage(
                icon: Icons.help_outline, title: 'Match introuvable')
            : _MatchTabs(match: m),
      ),
    );
  }
}

class _MatchTabs extends ConsumerWidget {
  const _MatchTabs({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Future<void> refresh() async {
      ref.invalidate(matchProvider(match.id));
      ref.invalidate(latestOddsProvider(match.id));
      ref.invalidate(storedAnalysisProvider(match.id));
      ref.invalidate(matchInsightsProvider(match.id));
      await ref.read(matchProvider(match.id).future);
    }

    return DefaultTabController(
      length: 4,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: MatchHeader(match: match)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Pronostic'),
                  Tab(text: 'Analyse'),
                  Tab(text: 'Marchés'),
                  Tab(text: 'Stats'),
                ],
              ),
              theme.scaffoldBackgroundColor,
            ),
          ),
        ],
        body: TabBarView(
          children: [
            RefreshIndicator(
                onRefresh: refresh, child: PronosticTab(match: match)),
            RefreshIndicator(
                onRefresh: refresh, child: AnalysisTab(match: match)),
            RefreshIndicator(
                onRefresh: refresh, child: MarketsTab(match: match)),
            RefreshIndicator(onRefresh: refresh, child: StatsTab(match: match)),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.background);

  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(
          color: background, elevation: overlapsContent ? 2 : 0, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate old) =>
      old.tabBar != tabBar || old.background != background;
}

/// En-tête : logos, noms, forme (5 derniers), score ou horaire, stade, analyse offerte.
class MatchHeader extends ConsumerWidget {
  const MatchHeader({super.key, required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = match;
    final insights = ref.watch(matchInsightsProvider(m.id)).valueOrNull;
    final featured = ref.watch(featuredMatchProvider).valueOrNull == m.id;

    Widget team(TeamRef t, List<FormEntry>? form) => Expanded(
          child: Column(
            children: [
              SportsLogo(url: t.logoUrl, size: 56),
              const SizedBox(height: 8),
              Text(t.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2),
              _FollowTeamButton(team: t),
              if (form != null && form.isNotEmpty) ...[
                const SizedBox(height: 6),
                // Du plus ancien au plus récent (le plus récent à droite).
                FormChips(
                    results: [for (final e in form.reversed) e.letter],
                    size: 20),
              ],
            ],
          ),
        );
    final center =
        m.hasScore ? '${m.homeGoals} - ${m.awayGoals}' : timeLabel(m.kickoffAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                [if (m.round != null) m.round!, _dateLine(m.kickoffAt)]
                    .join(' · '),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  team(m.home, insights?.homeForm),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Column(
                      children: [
                        Text(center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: m.isLive ? scheme.primary : null,
                            )),
                        Text(
                            m.status == MatchStatus.scheduled
                                ? 'Coup d’envoi'
                                : statusLabel(m),
                            style: theme.textTheme.labelMedium),
                        if (m.htHomeGoals != null &&
                            m.htAwayGoals != null &&
                            m.status != MatchStatus.scheduled)
                          Text('Mi-temps ${m.htHomeGoals}-${m.htAwayGoals}',
                              style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  team(m.away, insights?.awayForm),
                ],
              ),
              if (m.venue != null || m.referee != null) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    if (m.venue != null) m.venue!,
                    if (m.referee != null) 'Arbitre : ${m.referee}'
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (featured) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.card_giftcard,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Analyse offerte du jour',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// « Aujourd’hui 30/10 », « Demain 31/10 », sinon « sam. 31/10 » (année si différente).
String _dateLine(DateTime kickoff) {
  final label = dayLabel(kickoff, DateTime.now());
  return label.contains('/') ? label : '$label ${shortDate(kickoff)}';
}

/// Suivre une équipe : ses matchs passent en premier sur l'accueil.
class _FollowTeamButton extends ConsumerWidget {
  const _FollowTeamButton({required this.team});

  final TeamRef team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteTeamsProvider).valueOrNull;
    if (favorites == null) return const SizedBox(height: 4);
    final on = favorites.containsKey(team.id);
    return TextButton.icon(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: () async {
        try {
          await ref
              .read(communityRepositoryProvider)
              .setFavoriteTeam(team.id, !on);
          ref.invalidate(favoriteTeamsProvider);
          if (context.mounted) {
            showMessage(
                context,
                on
                    ? 'Vous ne suivez plus ${team.name}.'
                    : 'Vous suivez ${team.name} : ses matchs passent en premier sur l’accueil.');
          }
        } catch (e) {
          if (context.mounted) {
            showMessage(context, communityErrorMessage(e), error: true);
          }
        }
      },
      icon: Icon(on ? Icons.star : Icons.star_border, size: 18),
      label: Text(on ? 'Suivie' : 'Suivre'),
    );
  }
}

/// Texte de partage d'un match : affiche, date et lien qui ouvre la fiche dans l'application.
String matchShareText(MatchSummary m, String? link) => [
      '${m.home.name} – ${m.away.name}',
      '${m.competition.name} · ${shortDate(m.kickoffAt)} à ${timeLabel(m.kickoffAt)}',
      'Probabilités, forme et cotes sur Coupon Pro IA.',
      if (link != null) link,
      'Estimations, aucune certitude. 18+',
    ].join('\n');
