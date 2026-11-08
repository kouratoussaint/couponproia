import 'package:flutter/material.dart';
import 'package:coupon_pro_ia/core/router/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_colors.dart';
import '../matches/data/sports_format.dart';
import 'billing_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Accueil : forfait qui se termine (3 jours) ou vient de se terminer, avec « Renouveler ».
class RenewalBanner extends ConsumerWidget {
  const RenewalBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(renewalProvider).valueOrNull;
    if (r == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = r.ended ? theme.colorScheme.error : BrandColors.orange;
    final plan = r.planCode.replaceAll('_', ' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: color.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.6))),
        child: ListTile(
          leading:
              Icon(r.ended ? Icons.event_busy : Icons.schedule, color: color),
          title: Text(r.ended
              ? trf('Votre forfait {0} a pris fin', [plan])
              : trf('Votre forfait {0} se termine le {1}',
                  [plan, shortDate(r.periodEnd)])),
          subtitle: Text(r.ended
              ? tr('Renouvelez pour retrouver tous les coupons et analyses.')
              : tr('Renouvelez en un geste : la durée s’ajoute à la fin.')),
          trailing: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => context.openRoute(r.route),
            child: Text(tr('Renouveler')),
          ),
        ),
      ),
    );
  }
}
