import 'package:flutter/material.dart';

import '../../core/widgets/coming_soon_view.dart';
import '../shell/app_drawer.dart';

class CouponsScreen extends StatelessWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const DrawerMenuButton(), title: const Text('Coupons')),
      body: const ComingSoonView(
        icon: Icons.receipt_long,
        title: 'Coupons',
        lot: 'LOT 4',
        description: 'Les coupons générés par le moteur IA de la plateforme, contrôlés avant publication, '
            'puis vos propres coupons.',
        features: [
          'Coupon du jour, prudent, équilibré, audacieux',
          'Justification de chaque sélection',
          'Suivi jusqu’au règlement (LOT 8)',
          'Mes coupons, favoris et historique',
        ],
      ),
    );
  }
}
