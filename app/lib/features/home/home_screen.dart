import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/app_logo.dart';
import '../analysis/data/analysis_format.dart';
import '../assistant/data/assistant_repository.dart';
import '../coupons/data/coupon_models.dart';
import '../coupons/data/coupon_repository.dart';
import '../coupons/presentation/coupon_widgets.dart';
import '../matches/data/insights_models.dart';
import '../matches/data/sports_format.dart';
import '../matches/data/sports_models.dart';
import '../matches/data/sports_repository.dart';
import '../matches/presentation/sports_widgets.dart';
import '../community/data/community_repository.dart';
import '../onboarding/data/preferences_repository.dart';
import '../onboarding/presentation/onboarding_sheet.dart';
import '../profile/data/profile_repository.dart';
import '../shell/app_drawer.dart';

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche'
];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// Matchs à mettre en avant : pas encore terminés, compétitions suivies puis prioritaires d'abord.
List<MatchSummary> highlightedMatches(List<MatchSummary> all,
    {int max = 5, Set<int> favorites = const {}, Set<int> teams = const {}}) {
  // Équipes suivies d'abord, puis compétitions suivies, puis priorité.
  int fav(MatchSummary m) =>
      teams.contains(m.home.id) || teams.contains(m.away.id)
          ? 0
          : favorites.contains(m.competition.id)
              ? 1
              : 2;
  final open =
      all.where((m) => m.status == MatchStatus.scheduled || m.isLive).toList()
        ..sort((a, b) {
          final f = fav(a).compareTo(fav(b));
          if (f != 0) return f;
          final p = a.competition.priority.compareTo(b.competition.priority);
          return p != 0 ? p : a.kickoffAt.compareTo(b.kickoffAt);
        });
  return open.take(max).toList();
}

/// Coupon du jour : celui publié aujourd'hui, sinon le prochain encore ouvert.
Coupon? couponOfTheDay(List<Coupon> all, DateTime now) {
  final today = dateOnly(now);
  final candidates = all
      .where((c) => c.category == 'du_jour' && !c.isWithdrawn && c.isOpen(now))
      .toList()
    ..sort((a, b) => a.firstKickoffAt.compareTo(b.firstKickoffAt));
  for (final c in candidates) {
    if (dateOnly(c.publishedAt ?? c.publishAt) == today) return c;
  }
  return candidates.firstOrNull;
}

/// Accueil : coupon du jour, analyse offerte, matchs du jour et de demain, derniers résultats.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = ref.watch(myProfileProvider).valueOrNull?.displayName;
    final credits = ref.watch(myCreditsProvider).valueOrNull;
    final now = DateTime.now();
    final today = dateOnly(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    Future<void> refresh() async {
      ref.invalidate(myProfileProvider);
      ref.invalidate(publishedCouponsProvider);
      ref.invalidate(featuredMatchProvider);
      ref.invalidate(matchesOfDayProvider(today));
      ref.invalidate(matchesOfDayProvider(tomorrow));
      ref.invalidate(market1x2OfDayProvider(today));
      ref.invalidate(market1x2OfDayProvider(tomorrow));
      ref.invalidate(myCreditsProvider);
      await ref.read(publishedCouponsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const AppLogo(size: 30),
        actions: [
          if (credits != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(Icons.bolt, size: 18, color: scheme.primary),
                label: Text(credits.unlimited ? '∞' : '${credits.total}'),
                tooltip: 'Crédits IA',
                onPressed: () => context.push(AppRoutes.billing),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                children: [
                  Text(name == null ? 'Bonjour' : 'Bonjour, $name',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(longDate(now),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const OnboardingTrigger(),
            const _CouponOfTheDay(),
            const _FeaturedMatch(),
            _MatchesBlock(
                title: 'Matchs du jour',
                day: today,
                empty:
                    'Plus de match à venir aujourd’hui dans les compétitions suivies.'),
            _MatchesBlock(
                title: 'Matchs de demain',
                day: tomorrow,
                empty: 'Aucun match demain dans les compétitions suivies.'),
            const _RecentResults(),
            const _Shortcuts(),
            const SizedBox(height: 16),
            Text(
              'Les pronostics sont des estimations. Aucun gain n’est garanti. Interdit aux moins de 18 ans.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.title, {this.icon, this.action});

  final String title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
              child: Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
          if (action != null)
            Flexible(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: action!),
            ),
        ],
      ),
    );
  }
}

class _CouponOfTheDay extends ConsumerWidget {
  const _CouponOfTheDay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final coupons = ref.watch(publishedCouponsProvider);
    return coupons.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(userMessageFor(e)),
      data: (all) {
        final c = couponOfTheDay(all, DateTime.now());
        return Card(
          color: scheme.primary.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: c == null
                ? () => context.go(AppRoutes.coupons)
                : () => context.push(AppRoutes.couponDetailFor(c.id)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Coupon du jour',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (c != null && c.result != null)
                        ResultBadge(result: c.result, odd: c.settledOdd)
                      else if (c != null)
                        RiskBadge(risk: c.riskLevel, compact: true),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (c == null)
                    Text(
                      'Le coupon du jour est publié chaque matin, quand des matchs à venir ont des cotes '
                      'récentes. Sinon, le moteur s’abstient.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else ...[
                    for (final s in c.selections.take(3))
                      Text(
                        '${s.match.home} – ${s.match.away} · ${outcomeKeyLabel(s.key, s.match.home, s.match.away)}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (c.selections.length > 3)
                      Text('+ ${c.selections.length - 3} autre(s)',
                          style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Cote ${decimal(c.totalOdd)}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Probabilité estimée ${pct(c.combinedProbability)} · ${frequencyLabel(c.combinedProbability)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeaturedMatch extends ConsumerWidget {
  const _FeaturedMatch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = ref.watch(featuredMatchProvider).valueOrNull;
    final match = id == null ? null : ref.watch(matchProvider(id)).valueOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: match == null
            ? null
            : () => context.push(AppRoutes.matchDetailFor(match.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.card_giftcard, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Analyse offerte du jour',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (match != null)
                    Text(
                        '${match.competition.name} · ${timeLabel(match.kickoffAt)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 10),
              if (match == null)
                Text(
                  'Chaque matin, un match du jour est choisi et son analyse complète est ouverte à tous, '
                  'sans compter dans votre quota.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                Row(
                  children: [
                    SportsLogo(url: match.home.logoUrl, size: 26),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${match.home.name} – ${match.away.name}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    SportsLogo(url: match.away.logoUrl, size: 26),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text('Analyse complète offerte',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.primary)),
                    ),
                    FilledButton(
                      onPressed: () =>
                          context.push(AppRoutes.matchDetailFor(match.id)),
                      child: const Text('Voir l’analyse'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchesBlock extends ConsumerWidget {
  const _MatchesBlock(
      {required this.title, required this.day, required this.empty});

  final String title;
  final DateTime day;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchesOfDayProvider(day));
    final markets = ref.watch(market1x2OfDayProvider(day)).valueOrNull ??
        const <int, Market1x2>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockTitle(
          title,
          icon: Icons.sports_soccer,
          action: TextButton(
            onPressed: () => context.go(AppRoutes.matches),
            child: const Text('Tous les matchs'),
          ),
        ),
        matches.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (all) {
            final shown = highlightedMatches(all,
                favorites: ref
                        .watch(myPreferencesProvider)
                        .valueOrNull
                        ?.favoriteCompetitions ??
                    const {},
                teams: ref
                        .watch(favoriteTeamsProvider)
                        .valueOrNull
                        ?.keys
                        .toSet() ??
                    const {});
            if (shown.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(empty),
                ),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    MatchCard(match: shown[i], market: markets[shown[i].id]),
                  ],
                  if (markets.isNotEmpty) ...[
                    const OneXTwoLegend(),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RecentResults extends ConsumerWidget {
  const _RecentResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coupons = ref.watch(publishedCouponsProvider).valueOrNull;
    final settled = (coupons ?? const <Coupon>[])
        .where((c) => c.result != null && !c.isWithdrawn)
        .toList()
      ..sort((a, b) => (b.settledAt ?? b.lastKickoffAt)
          .compareTo(a.settledAt ?? a.lastKickoffAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockTitle('Derniers résultats',
            icon: Icons.fact_check_outlined,
            action: Text('5 derniers coupons réglés',
                style: theme.textTheme.labelSmall)),
        if (settled.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Les résultats apparaissent ici dès que les premiers coupons sont réglés, gagnés comme perdus.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final c in settled.take(5))
                  ListTile(
                    onTap: () => context.push(AppRoutes.couponDetailFor(c.id)),
                    title: Text(c.title, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${categoryLabels[c.category] ?? c.category} · cote ${decimal(c.totalOdd)} · '
                        '${shortDate(c.lastKickoffAt)}'),
                    trailing: ResultBadge(result: c.result, odd: c.settledOdd),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push(AppRoutes.performance),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Tout l’historique, pertes comprises'),
          ),
        ),
      ],
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.smart_toy_outlined,
        'Assistant IA',
        () => context.go(AppRoutes.assistant)
      ),
      (
        Icons.science_outlined,
        'Laboratoire',
        () => context.push(AppRoutes.lab)
      ),
      (Icons.palette_outlined, 'Studio', () => context.push(AppRoutes.studio)),
      (
        Icons.bookmarks_outlined,
        'Mes coupons',
        () => context.push(AppRoutes.myCoupons)
      ),
    ];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockTitle('Raccourcis', icon: Icons.grid_view),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.6,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (final (icon, label, onTap) in items)
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, style: theme.textTheme.titleSmall),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Propose le premier lancement une seule fois (tant qu'il n'est ni terminé ni passé).
class OnboardingTrigger extends ConsumerStatefulWidget {
  const OnboardingTrigger({super.key});

  @override
  ConsumerState<OnboardingTrigger> createState() => _OnboardingTriggerState();
}

class _OnboardingTriggerState extends ConsumerState<OnboardingTrigger> {
  static bool _shownThisSession = false;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(myPreferencesProvider).valueOrNull;
    if (prefs != null && prefs.needsOnboarding && !_shownThisSession) {
      _shownThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOnboarding(context);
      });
    }
    return const SizedBox.shrink();
  }
}
