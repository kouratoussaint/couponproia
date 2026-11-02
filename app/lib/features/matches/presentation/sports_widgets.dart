import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../data/insights_models.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Logo d'équipe ou de compétition, mis en cache sur l'appareil (économie de données).
class SportsLogo extends StatelessWidget {
  const SportsLogo(
      {super.key,
      required this.url,
      this.size = 24,
      this.fallback = Icons.shield_outlined});

  final String? url;
  final double size;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(fallback,
        size: size * 0.9,
        color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (url == null || url!.isEmpty) {
      return SizedBox(width: size, height: size, child: placeholder);
    }
    return CachedNetworkImage(
      imageUrl: url!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      memCacheWidth: (size * 3).round(),
      placeholder: (_, __) => SizedBox(width: size, height: size),
      errorWidget: (_, __, ___) =>
          SizedBox(width: size, height: size, child: placeholder),
    );
  }
}

/// Ligne d'un match dans les listes.
class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, this.market, this.action});

  final MatchSummary match;

  /// Action à droite (bouton « Analyser »), facultative.
  final Widget? action;

  /// Répartition 1/N/2 selon les cotes (affichée tant que le match n'est pas joué).
  final Market1x2? market;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = match;
    final live = m.isLive;
    final statusStyle = theme.textTheme.labelMedium?.copyWith(
      color: live ? scheme.primary : scheme.onSurfaceVariant,
      fontWeight: live ? FontWeight.w700 : FontWeight.w500,
    );

    Widget teamRow(TeamRef team, int? goals, bool winner) => Row(
          children: [
            SportsLogo(url: team.logoUrl, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                team.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: winner ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
            if (goals != null)
              Text(
                '$goals',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: live ? scheme.primary : null),
              ),
          ],
        );

    final homeWins = m.hasScore &&
        m.status == MatchStatus.finished &&
        m.homeGoals! > m.awayGoals!;
    final awayWins = m.hasScore &&
        m.status == MatchStatus.finished &&
        m.awayGoals! > m.homeGoals!;

    return InkWell(
      onTap: () => context.push(AppRoutes.matchDetailFor(m.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                          color: scheme.primary, shape: BoxShape.circle),
                    ),
                  Text(statusLabel(m), style: statusStyle),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  teamRow(m.home, m.homeGoals, homeWins),
                  const SizedBox(height: 6),
                  teamRow(m.away, m.awayGoals, awayWins),
                  if (market != null && !m.hasScore) ...[
                    const SizedBox(height: 8),
                    OneXTwoBar(market: market!),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 10),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Barre 1 / N / 2 en trois segments : équipe qui reçoit, nul, équipe visiteuse.
class OneXTwoBar extends StatelessWidget {
  const OneXTwoBar({super.key, required this.market, this.height = 6});

  final Market1x2 market;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    int flex(double p) => (p * 1000).round().clamp(1, 1000);
    return Semantics(
      label:
          trf('Selon les cotes : domicile {0} %, nul {1} %, extérieur {2} %', [
        (market.pHome * 100).round(),
        (market.pDraw * 100).round(),
        (market.pAway * 100).round()
      ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                  flex: flex(market.pHome),
                  child: Container(color: BrandColors.vertIA)),
              const SizedBox(width: 2),
              Expanded(
                  flex: flex(market.pDraw),
                  child: Container(color: scheme.outline)),
              const SizedBox(width: 2),
              Expanded(
                  flex: flex(market.pAway),
                  child: Container(color: BrandColors.orange)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Légende de la barre 1 / N / 2.
class OneXTwoLegend extends StatelessWidget {
  const OneXTwoLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 14,
                height: 6,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(tr('Selon les cotes :'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          key(BrandColors.vertIA, 'domicile'),
          key(theme.colorScheme.outline, 'nul'),
          key(BrandColors.orange, tr('extérieur')),
        ],
      ),
    );
  }
}

/// Pastilles V / N / D de la forme récente.
class FormChips extends StatelessWidget {
  const FormChips({super.key, required this.results, this.size = 26});

  final List<String> results;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorFor(String r) => switch (r) {
          'V' => scheme.primary,
          'D' => scheme.error,
          _ => scheme.onSurfaceVariant,
        };
    return Wrap(
      spacing: 4,
      children: [
        for (final r in results)
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorFor(r).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(size / 4),
              border: Border.all(color: colorFor(r)),
            ),
            child: Text(formLetterShown(r),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.5,
                    color: colorFor(r))),
          ),
      ],
    );
  }
}

/// Titre de section dans les fiches.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Message d'état (vide, erreur) centré.
class InfoMessage extends StatelessWidget {
  const InfoMessage(
      {super.key,
      required this.icon,
      required this.title,
      this.body,
      this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
