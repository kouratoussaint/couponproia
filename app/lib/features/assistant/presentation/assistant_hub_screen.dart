import 'package:flutter/material.dart';

import '../../../core/widgets/sub_tab_back.dart';

import '../../lab/presentation/lab_screen.dart';
import '../../shell/app_drawer.dart';
import 'assistant_screen.dart';
import 'my_coupons_screen.dart';
import '../../help/help_screens.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Onglet « Assistant IA » de la barre du bas : trois onglets, Assistant (conversation),
/// Mes coupons (coupons enregistrés) et Laboratoire (composition et calculs).
class AssistantHubScreen extends StatelessWidget {
  const AssistantHubScreen({super.key, this.initialTab = 0, this.labCouponId});

  /// 0 Assistant, 1 Mes coupons, 2 Laboratoire.
  final int initialTab;

  /// Coupon enregistré à ouvrir dans le Laboratoire (`&coupon=` dans l'adresse).
  final String? labCouponId;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab.clamp(0, 2),
        child: SubTabBackScope(
            shellTab: 3,
            child: Scaffold(
              appBar: AppBar(
                leading: const DrawerMenuButton(),
                title: Text(tr('Assistant IA')),
                actions: [
                  Builder(builder: (context) {
                    final tabs = DefaultTabController.of(context);
                    return AnimatedBuilder(
                      animation: tabs,
                      builder: (_, __) => HelpButton(const [
                        'assistant',
                        'mes-coupons',
                        'laboratoire'
                      ][tabs.index]),
                    );
                  }),
                ],
                bottom: TabBar(
                  tabs: [
                    Tab(text: tr('Assistant')),
                    Tab(text: tr('Mes coupons')),
                    Tab(text: tr('Laboratoire')),
                  ],
                ),
              ),
              body: TabBarView(
                // Glisser sur la conversation ne doit pas changer d'onglet par erreur.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const AssistantScreen(embedded: true),
                  const MyCouponsScreen(embedded: true),
                  LabScreen(embedded: true, initialCouponId: labCouponId),
                ],
              ),
            )),
      );
}

/// Onglet demandé dans l'adresse : `/assistant?onglet=coupons` ou `?onglet=laboratoire`.
int assistantTabFrom(String? value) => switch (value) {
      'coupons' => 1,
      'laboratoire' => 2,
      _ => 0,
    };
