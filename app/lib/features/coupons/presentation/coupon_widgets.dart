import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../../analysis/data/analysis_models.dart';
import '../../analysis/presentation/analysis_section.dart';
import '../../matches/presentation/sports_widgets.dart';

import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../data/coupon_models.dart';

/// Pastille de risque estimé (jamais présentée comme une garantie).
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.risk, this.compact = false});

  final String risk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (risk) {
      'prudent' => scheme.primary,
      'equilibre' => BrandColors.orange,
      _ => scheme.error,
    };
    final text = compact
        ? const {
              'prudent': 'Prudent',
              'equilibre': 'Équilibré',
              'audacieux': 'Audacieux'
            }[risk] ??
            risk
        : riskLabels[risk] ?? risk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Résultat réglé d'un coupon ou d'une sélection (gagné, perdu, annulé) ou « en cours ».
class ResultBadge extends StatelessWidget {
  const ResultBadge({super.key, required this.result, this.odd});

  final String? result;
  final double? odd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (result) {
      'won' => (scheme.primary, Icons.check_circle),
      'lost' => (scheme.error, Icons.cancel),
      'void' => (scheme.outline, Icons.remove_circle_outline),
      _ => (scheme.onSurfaceVariant, Icons.schedule),
    };
    final label = result == null
        ? 'En cours'
        : '${resultLabels[result] ?? result}${result == 'won' && odd != null ? ' · ${decimal(odd!)}' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

String couponDateLabel(DateTime local, DateTime now) =>
    '${dayLabel(local, now)} ${shortDate(local)} · ${timeLabel(local)}';

class CouponCard extends StatelessWidget {
  const CouponCard(
      {super.key, required this.coupon, required this.onTap, this.trailing});

  final Coupon coupon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = coupon;
    final now = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(categoryLabels[c.category] ?? c.category,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                  if (c.result != null && !c.isWithdrawn)
                    ResultBadge(result: c.result, odd: c.settledOdd)
                  else if (c.isWithdrawn)
                    Text('Retiré',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.error))
                  else
                    RiskBadge(risk: c.riskLevel, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(c.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (c.locked)
                Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'Réservé aux forfaits payants jusqu’au coup d’envoi',
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              for (final s in c.selections.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${s.match.home} – ${s.match.away} · ${outcomeKeyLabel(s.key, s.match.home, s.match.away)}',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (c.selections.length > 4)
                Text('+ ${c.selections.length - 4} autre(s)',
                    style: theme.textTheme.bodySmall),
              const Divider(height: 18),
              Row(
                children: [
                  Text('Cote ${decimal(c.totalOdd)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(width: 12),
                  Text('Modèle ${pct(c.combinedProbability)}',
                      style: theme.textTheme.bodySmall),
                  const Spacer(),
                  trailing ??
                      Text(
                        'Début ${couponDateLabel(c.firstKickoffAt, now)}',
                        style: theme.textTheme.labelSmall,
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte d'une sélection : match, issue, cote conservée, probabilités, fiabilité, justification.
class SelectionCard extends StatelessWidget {
  const SelectionCard({super.key, required this.selection, this.currentOdd});

  final CouponSelection selection;
  final double? currentOdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = selection;
    final m = s.match;
    final now = DateTime.now();
    final played =
        m.homeGoals != null && m.awayGoals != null && m.status != 'scheduled';
    final changed = currentOdd != null && (currentOdd! - s.odd).abs() >= 0.01;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.matchDetailFor(m.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${m.competition} · ${dayLabel(m.kickoffAt, now)} ${shortDate(m.kickoffAt)} à ${timeLabel(m.kickoffAt)}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SportsLogo(url: m.homeLogo, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      played
                          ? '${m.home} ${m.homeGoals}-${m.awayGoals} ${m.away}'
                          : '${m.home} – ${m.away}',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SportsLogo(url: m.awayLogo, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(outcomeKeyLabel(s.key, m.home, m.away),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (s.result != null) ...[
                    ResultBadge(result: s.result),
                    const SizedBox(width: 8),
                  ],
                  Text(decimal(s.odd),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ReliabilityChip(
                      reliability: Reliability.parse(s.reliability)),
                  Text('Modèle ${pct(s.modelProbability)}',
                      style: theme.textTheme.labelMedium),
                  if (s.impliedProbability != null)
                    Text('Marché ${pct(s.impliedProbability!)}',
                        style: theme.textTheme.labelMedium),
                  if (s.edge != null)
                    Text(
                      'Écart ${edgePoints(s.edge!)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: s.edge! > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(s.justification, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                'Cote médiane de ${s.bookmakers ?? '?'} bookmakers relevée le ${shortDate(s.oddsCapturedAt)} à ${timeLabel(s.oddsCapturedAt)}'
                '${changed ? ' · cote actuelle ${decimal(currentOdd!)} (la cote publiée est conservée)' : ''}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenu d'un coupon réservé : visible avec un forfait payant, ou par tous au coup d'envoi.
class LockedCouponNotice extends StatelessWidget {
  const LockedCouponNotice({super.key, required this.firstKickoffAt});

  final DateTime firstKickoffAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Coupon réservé',
                        style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Les sélections et l’analyse de ce coupon sont accessibles avec un forfait STARTER ou supérieur. '
              'Elles deviennent visibles par tous au premier coup d’envoi '
              '(${shortDate(firstKickoffAt)} à ${timeLabel(firstKickoffAt)}). Le coupon du jour reste gratuit.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.billing),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Voir les forfaits'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
