import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';

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
  const MatchCard({super.key, required this.match});

  final MatchSummary match;

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastilles V / N / D de la forme récente.
class FormChips extends StatelessWidget {
  const FormChips({super.key, required this.results});

  final List<String> results;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorFor(String r) => switch (r) {
          'V' => scheme.primary,
          'D' => scheme.error,
          _ => scheme.outline,
        };
    return Wrap(
      spacing: 4,
      children: [
        for (final r in results)
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorFor(r).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorFor(r)),
            ),
            child: Text(r,
                style:
                    TextStyle(fontWeight: FontWeight.w700, color: colorFor(r))),
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
