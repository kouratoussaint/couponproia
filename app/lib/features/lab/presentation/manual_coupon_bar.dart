import 'package:flutter/material.dart';
import 'package:coupon_pro_ia/core/router/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_routes.dart';
import '../../analysis/data/analysis_format.dart';
import '../data/lab_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Barre du coupon en construction (générateur manuel), visible dès qu'une cote est choisie.
class ManualCouponBar extends ConsumerWidget {
  const ManualCouponBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(manualCouponProvider);
    if (picks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Material(
        color: scheme.primaryContainer,
        child: InkWell(
          onTap: () => context.openRoute(AppRoutes.assistantLab),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.receipt_long, color: scheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trf('Mon coupon : {0} sélection{1} · cote indicative {2}', [
                      picks.length,
                      picks.length > 1 ? 's' : '',
                      decimal(indicativeOdd(picks))
                    ]),
                    style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Text(tr('Ouvrir'),
                    style: TextStyle(color: scheme.onPrimaryContainer)),
                Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
