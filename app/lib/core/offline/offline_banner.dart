import 'package:flutter/material.dart';

import 'offline_http_client.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Bandeau discret en bas de l'écran quand l'app affiche des données enregistrées.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget? child;

  static String label(DateTime at, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(at.hour)}:${two(at.minute)}';
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return trf('Hors connexion · données {0}', [
      sameDay
          ? trf('de {0}', [time])
          : trf('du {0}/{1} à {2}', [two(at.day), two(at.month), time])
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child ?? const SizedBox.shrink()),
        ValueListenableBuilder<DateTime?>(
          valueListenable: offlineSince,
          builder: (context, since, _) {
            if (since == null) return const SizedBox.shrink();
            final scheme = Theme.of(context).colorScheme;
            return Material(
              color: scheme.inverseSurface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          size: 18, color: scheme.onInverseSurface),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(label(since, DateTime.now()),
                            style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
