import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/brand_colors.dart';
import '../../core/widgets/app_logo.dart';
import '../analysis/data/analysis_format.dart';
import '../analysis/presentation/analyze_access.dart';
import '../assistant/data/assistant_repository.dart';
import '../coupons/data/coupon_models.dart';
import '../coupons/data/coupon_phase.dart';
import '../coupons/data/coupon_repository.dart';
import '../coupons/coupons_screen.dart' show couponsTabRequestProvider;
import '../coupons/presentation/coupon_tiles.dart';
import '../coupons/presentation/coupon_widgets.dart';
import '../matches/data/insights_models.dart';
import '../matches/data/sports_format.dart';
import '../matches/data/sports_models.dart';
import '../matches/data/sports_repository.dart';
import '../community/data/community_repository.dart';
import '../notifications/data/notifications_repository.dart';
import '../notifications/presentation/notifications_screens.dart';
import '../legal/legal_repository.dart';
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

/// Accueil (maquette validée le 31/10) : un en-tête aéré, trois chiffres du jour, le coupon
/// du jour mis en avant, quatre raccourcis, l'analyse offerte, un seul bloc de matchs
/// (aujourd'hui / demain) et le bilan de la semaine.
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
    final date = longDate(now);

    Future<void> refresh() async {
      ref.invalidate(myProfileProvider);
      ref.invalidate(publishedCouponsProvider);
      ref.invalidate(featuredMatchProvider);
      ref.invalidate(matchesOfDayProvider(today));
      ref.invalidate(matchesOfDayProvider(tomorrow));
      ref.invalidate(market1x2OfDayProvider(today));
      ref.invalidate(market1x2OfDayProvider(tomorrow));
      ref.invalidate(myCreditsProvider);
      ref.invalidate(unreadCountProvider);
      await ref.read(publishedCouponsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const AppLogo(size: 30),
        actions: [
          const NotificationBell(),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(name == null ? 'Bonjour' : 'Bonjour, $name',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${date[0].toUpperCase()}${date.substring(1)}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            const OnboardingTrigger(),
            _StatusTiles(day: today),
            _LiveBlock(day: today),
            const SizedBox(height: 16),
            const _FeaturedMatch(),
            const SizedBox(height: 16),
            const _CouponOfTheDay(),
            const SizedBox(height: 24),
            _MatchesBlock(today: today, tomorrow: tomorrow),
            const SizedBox(height: 24),
            const _LastCoupons(),
            const SizedBox(height: 24),
            const _Shortcuts(),
            const SizedBox(height: 20),
            Text(
              'Les pronostics sont des estimations, jamais des certitudes. Interdit aux moins de 18 ans.',
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

/// Carte blanche à bord fin, coins arrondis : la surface de base de l'accueil.
class _Surface extends StatelessWidget {
  const _Surface(
      {required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(14),
      this.radius = 18,
      this.highlight = false});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
            color: highlight ? scheme.primary : scheme.outlineVariant,
            width: highlight ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Petit titre en capitales vertes (« COUPON DU JOUR »).
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9));
  }
}

/// Trois chiffres du jour : coupons à jouer, en cours, heure du premier match.
class _StatusTiles extends ConsumerWidget {
  const _StatusTiles({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final coupons = ref.watch(publishedCouponsProvider).valueOrNull;
    final open = [
      for (final c in coupons ?? const <Coupon>[])
        if (!c.isWithdrawn && c.result == null) c
    ];
    final split = splitActive(open, now);
    final matches = ref.watch(matchesOfDayProvider(day)).valueOrNull;
    final upcoming = (matches ?? const <MatchSummary>[])
        .where((m) =>
            m.status == MatchStatus.scheduled && m.kickoffAt.isAfter(now))
        .map((m) => m.kickoffAt)
        .toList()
      ..sort();
    final ready = coupons != null;
    Widget tile(String value, String label, VoidCallback onTap,
            {bool accent = false}) =>
        Expanded(
          child: _Surface(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: accent
                              ? Theme.of(context).colorScheme.primary
                              : null)),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(ready ? '${split.toPlay.length}' : '–', 'à jouer',
            () => context.go(AppRoutes.coupons),
            accent: split.toPlay.isNotEmpty),
        const SizedBox(width: 10),
        tile(ready ? '${split.live.length}' : '–', 'en cours',
            () => context.go(AppRoutes.coupons)),
        const SizedBox(width: 10),
        tile(
            upcoming.isEmpty ? '–' : timeLabel(upcoming.first),
            upcoming.isEmpty ? 'plus de match' : '1er match',
            () => context.go(AppRoutes.matches)),
      ],
    );
  }
}

class _CouponOfTheDay extends ConsumerWidget {
  const _CouponOfTheDay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final coupons = ref.watch(publishedCouponsProvider);
    return coupons.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(userMessageFor(e)),
      data: (all) {
        final c = couponOfTheDay(all, DateTime.now());
        if (c == null) {
          return _Surface(
            highlight: true,
            radius: 20,
            padding: const EdgeInsets.all(18),
            onTap: () => context.go(AppRoutes.coupons),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow('Coupon du jour'),
                const SizedBox(height: 8),
                Text(
                  'Le coupon du jour est publié chaque matin, quand des matchs à venir ont des cotes '
                  'récentes. Sinon, le moteur s’abstient.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }
        final sels = c.selections;
        final first =
            sels.isEmpty ? c.firstKickoffAt : sels.first.match.kickoffAt;
        final last = sels.isEmpty ? c.lastKickoffAt : sels.last.match.kickoffAt;
        return _Surface(
          highlight: true,
          radius: 20,
          padding: const EdgeInsets.all(18),
          onTap: () => context.push(AppRoutes.couponDetailFor(c.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Eyebrow('Coupon du jour'),
                        const SizedBox(height: 6),
                        Text(
                          c.locked || sels.isEmpty
                              ? 'Sélections visibles avec un forfait, ou au coup d’envoi'
                              : '${sels.length} sélection${sels.length > 1 ? 's' : ''}'
                                  '${sels.isEmpty ? '' : timeLabel(first) == timeLabel(last) ? ' · ${timeLabel(first)}' : ' · de ${timeLabel(first)} à ${timeLabel(last)}'}',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(decimal(c.totalOdd),
                          style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800, height: 1)),
                      const SizedBox(height: 4),
                      if (c.result != null)
                        ResultBadge(result: c.result, odd: c.settledOdd)
                      else
                        Text('${pct(c.combinedProbability)} estimé',
                            style: muted),
                    ],
                  ),
                ],
              ),
              if (sels.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 12),
                for (final s in sels.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 46),
                          child: Text(timeLabel(s.match.kickoffAt),
                              softWrap: false,
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${s.match.home} – ${s.match.away}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              Text(
                                  outcomeKeyLabel(
                                      s.key, s.match.home, s.match.away),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: muted),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(decimal(s.odd),
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                if (sels.length > 4)
                  Text(
                      '+ ${sels.length - 4} autre${sels.length - 4 > 1 ? 's' : ''}',
                      style: muted),
              ],
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: () => context.push(AppRoutes.couponDetailFor(c.id)),
                child: const Text('Voir le coupon'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = [
      (
        Icons.smart_toy_outlined,
        'Assistant',
        () => context.go(AppRoutes.assistant)
      ),
      (
        Icons.bookmarks_outlined,
        'Mes coupons',
        () => context.push(AppRoutes.myCoupons)
      ),
      (
        Icons.science_outlined,
        'Laboratoire',
        () => context.push(AppRoutes.lab)
      ),
      (Icons.palette_outlined, 'Studio', () => context.push(AppRoutes.studio)),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, label, onTap) in items)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Icon(icon, color: scheme.primary),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FeaturedMatch extends ConsumerWidget {
  const _FeaturedMatch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // Cadeau : teinte dorée, distincte du vert des coupons.
    const gold = BrandColors.orange;
    final ink = dark ? const Color(0xFFF4C46B) : const Color(0xFF8A5300);
    final id = ref.watch(featuredMatchProvider).valueOrNull;
    final match = id == null ? null : ref.watch(matchProvider(id)).valueOrNull;
    return Material(
      color: gold.withValues(alpha: dark ? 0.16 : 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: gold.withValues(alpha: 0.75), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: match == null
            ? null
            : () => context.push(AppRoutes.matchDetailFor(match.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: gold,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.card_giftcard,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CADEAU · ANALYSE OFFERTE DU JOUR',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 3),
                        if (match == null)
                          Text(
                            'Chaque matin, un match est choisi et son analyse complète est offerte à tous, '
                            'sans crédit.',
                            style: theme.textTheme.bodyMedium,
                          )
                        else ...[
                          Text('${match.home.name} – ${match.away.name}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                              '${match.competition.name} · ${timeLabel(match.kickoffAt)} · gratuite, sans crédit',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (match != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: const Color(0xFF2B1A00),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () =>
                      context.push(AppRoutes.matchDetailFor(match.id)),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Voir l’analyse offerte'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Un seul bloc de matchs : bascule Aujourd'hui / Demain, lignes compactes avec la
/// répartition 1 · N · 2 selon le marché, cinq matchs puis « Tout voir ».
class _MatchesBlock extends ConsumerStatefulWidget {
  const _MatchesBlock({required this.today, required this.tomorrow});

  final DateTime today;
  final DateTime tomorrow;

  @override
  ConsumerState<_MatchesBlock> createState() => _MatchesBlockState();
}

class _MatchesBlockState extends ConsumerState<_MatchesBlock> {
  bool _tomorrow = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = _tomorrow ? widget.tomorrow : widget.today;
    final matches = ref.watch(matchesOfDayProvider(day));
    final markets = ref.watch(market1x2OfDayProvider(day)).valueOrNull ??
        const <int, Market1x2>{};
    Widget seg(String label, bool value) {
      final selected = _tomorrow == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() => _tomorrow = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  selected ? scheme.surfaceContainerLowest : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant)),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Matchs',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.matches),
              child: const Text('Tout voir'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    seg('Aujourd’hui', false),
                    const SizedBox(width: 3),
                    seg('Demain', true),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text('Marché : 1 · N · 2',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
              return _Surface(
                child: Text(_tomorrow
                    ? 'Aucun match demain dans les compétitions suivies.'
                    : 'Plus de match à venir aujourd’hui dans les compétitions suivies.'),
              );
            }
            return _Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                    _MatchRow(match: shown[i], market: markets[shown[i].id]),
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

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, this.market});

  final MatchSummary match;
  final Market1x2? market;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = match;
    final mk = market;
    int p(double v) => (v * 100).round();
    return InkWell(
      onTap: () => context.push(AppRoutes.matchDetailFor(m.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 46),
                child: m.isLive
                    ? Text(m.elapsed == null ? 'Direct' : '${m.elapsed}’',
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: BrandColors.rouge,
                            fontWeight: FontWeight.w800))
                    : Text(timeLabel(m.kickoffAt),
                        softWrap: false,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        m.isLive && m.hasScore
                            ? '${m.home.name} ${m.homeGoals}-${m.awayGoals} ${m.away.name}'
                            : '${m.home.name} – ${m.away.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(m.competition.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (mk != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${p(mk.pHome)} · ${p(mk.pDraw)} · ${p(mk.pAway)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 84,
                          height: 5,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Row(
                              children: [
                                Expanded(
                                    flex: p(mk.pHome).clamp(1, 100),
                                    child: Container(
                                        color: BrandColors.vertIAContraste)),
                                const SizedBox(width: 2),
                                Expanded(
                                    flex: p(mk.pDraw).clamp(1, 100),
                                    child: Container(color: scheme.outline)),
                                const SizedBox(width: 2),
                                Expanded(
                                    flex: p(mk.pAway).clamp(1, 100),
                                    child:
                                        Container(color: BrandColors.orange)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              AnalyzeMatchButton(match: m, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Les 5 derniers coupons réglés (gagnés comme perdus), avec le bilan des 7 derniers jours
/// et « Tout voir » vers l'onglet Résultats.
class _LastCoupons extends ConsumerWidget {
  const _LastCoupons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = ref.watch(publishedCouponsProvider).valueOrNull;
    final settled = [
      for (final c in all ?? const <Coupon>[])
        if (c.result != null && !c.isWithdrawn) c
    ]..sort((a, b) => (b.settledAt ?? b.lastKickoffAt)
        .compareTo(a.settledAt ?? a.lastKickoffAt));
    final since = DateTime.now().subtract(const Duration(days: 7));
    final week = settled
        .where((c) => (c.settledAt ?? c.lastKickoffAt).isAfter(since))
        .toList();
    final won = week.where((c) => c.result == 'won').length;
    final lost = week.where((c) => c.result == 'lost').length;
    void openAll() {
      ref.read(couponsTabRequestProvider.notifier).state = 2;
      context.go(AppRoutes.coupons);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Derniers coupons',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton(onPressed: openAll, child: const Text('Tout voir')),
          ],
        ),
        Text(
          week.isEmpty
              ? '7 derniers jours : pas encore de coupon réglé · pertes toujours comprises'
              : '7 derniers jours : $won gagné${won > 1 ? 's' : ''} · $lost perdu${lost > 1 ? 's' : ''}'
                  ' sur ${week.length} réglé${week.length > 1 ? 's' : ''} · pertes comprises',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (all == null)
          const LinearProgressIndicator()
        else if (settled.isEmpty)
          _Surface(
            child: Text(
                'Les résultats apparaissent ici dès que les premiers coupons sont réglés, gagnés comme perdus.',
                style: theme.textTheme.bodyMedium),
          )
        else
          for (final c in settled.take(5))
            ResultCouponTile(
              coupon: c,
              onTap: () => context.push(AppRoutes.couponDetailFor(c.id)),
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
    // Après l'acceptation des conditions (l'écran d'acceptation passe avant).
    final legal = ref.watch(legalStatusProvider);
    final legalDone = legal.hasError || (legal.valueOrNull?.isEmpty ?? false);
    if (prefs != null &&
        legalDone &&
        prefs.needsOnboarding &&
        !_shownThisSession) {
      _shownThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showOnboarding(context);
      });
    }
    return const SizedBox.shrink();
  }
}

/// Matchs en cours (score et minute), rafraîchis chaque minute tant que l'accueil est affiché.
class _LiveBlock extends ConsumerStatefulWidget {
  const _LiveBlock({required this.day});

  final DateTime day;

  @override
  ConsumerState<_LiveBlock> createState() => _LiveBlockState();
}

class _LiveBlockState extends ConsumerState<_LiveBlock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final live = ref
              .read(matchesOfDayProvider(widget.day))
              .valueOrNull
              ?.any((m) => m.isLive) ??
          false;
      if (live && mounted) ref.invalidate(matchesOfDayProvider(widget.day));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = ref.watch(matchesOfDayProvider(widget.day)).valueOrNull ??
        const <MatchSummary>[];
    final teams = ref.watch(favoriteTeamsProvider).valueOrNull?.keys.toSet() ??
        const <int>{};
    final live = all.where((m) => m.isLive).toList()
      ..sort((a, b) {
        int fav(MatchSummary m) =>
            teams.contains(m.home.id) || teams.contains(m.away.id) ? 0 : 1;
        final f = fav(a).compareTo(fav(b));
        return f != 0
            ? f
            : a.competition.priority.compareTo(b.competition.priority);
      });
    if (live.isEmpty) return const SizedBox.shrink();
    final shown = live.take(4).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: BrandColors.rouge, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('En direct (${live.length})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text('mis à jour toutes les 5 min',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            for (final m in shown)
              InkWell(
                onTap: () => context.push(AppRoutes.matchDetailFor(m.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(m.elapsed == null ? '–' : '${m.elapsed}’',
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: BrandColors.rouge,
                                fontWeight: FontWeight.w800)),
                      ),
                      Expanded(
                        child: Text('${m.home.name} – ${m.away.name}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(
                          m.hasScore
                              ? '${m.homeGoals} - ${m.awayGoals}'
                              : '0 - 0',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            if (live.length > shown.length)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.matches),
                  child: Text(
                      '+ ${live.length - shown.length} autre${live.length - shown.length > 1 ? 's' : ''}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
