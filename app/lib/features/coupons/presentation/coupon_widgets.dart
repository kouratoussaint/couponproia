import 'package:flutter/material.dart';

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
      'equilibre' => scheme.tertiary,
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
                  if (c.isWithdrawn)
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
