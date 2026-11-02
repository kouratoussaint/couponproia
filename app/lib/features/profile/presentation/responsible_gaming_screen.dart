import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../journal/data/journal_repository.dart';
import '../../simulator/data/stake_math.dart';
import '../../simulator/presentation/stake_simulator_sheet.dart';
import '../../system/system_providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Jeu responsable : repères simples, sans jugement, et outils disponibles dans l'app.
class ResponsibleGamingScreen extends StatelessWidget {
  const ResponsibleGamingScreen({super.key});

  static final _tips = [
    (
      tr('Fixez un budget'),
      tr('Décidez à l’avance d’une somme que vous pouvez perdre sans conséquence, et arrêtez-vous quand elle est atteinte.')
    ),
    (
      tr('Ne courez pas après vos pertes'),
      tr('Augmenter les mises pour « se refaire » mène presque toujours à des pertes plus grandes.')
    ),
    (
      tr('Pas d’argent nécessaire'),
      tr('Ne pariez jamais l’argent du loyer, de la nourriture, de l’école ou des dettes.')
    ),
    (
      tr('Faites des pauses'),
      tr('Le football reste un plaisir : prenez des jours sans paris.')
    ),
    (
      tr('Gardez l’esprit critique'),
      tr('Nos chiffres sont des estimations. Un coupon peut perdre même quand l’analyse est juste.')
    ),
  ];

  static final _signs = [
    tr('Vous pariez plus que prévu, ou de plus en plus souvent.'),
    tr('Vous cachez vos paris à vos proches.'),
    tr('Vous empruntez ou vendez des biens pour parier.'),
    tr('Le jeu vous rend nerveux, irritable ou vous empêche de dormir.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Jeu responsable'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            tr('Coupon Pro IA propose des analyses et des estimations. Nous ne prenons aucun pari et aucun gain n’est garanti. Les paris sportifs sont interdits aux moins de 18 ans.'),
            style: theme.textTheme.bodyLarge,
          ),
          SectionTitle(tr('Mon budget')),
          const BudgetCard(),
          SectionTitle(tr('Bonnes pratiques')),
          for (final (title, text) in _tips)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(title),
                    subtitle: Text(text))),
          SectionTitle(tr('Signes d’alerte')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in _signs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [const Text('•  '), Expanded(child: Text(s))],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    tr('Si vous vous reconnaissez, parlez-en à un proche ou à un professionnel de santé. Demander de l’aide est une bonne décision.'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          SectionTitle(tr('Dans l’app')),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: Text(tr('Couper les notifications')),
                  subtitle:
                      Text(tr('Toutes, ou seulement les nouveaux coupons')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(tr('Supprimer mon compte')),
                  subtitle: Text(tr('Depuis l’écran Profil, à tout moment')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.profile),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contacter le support : adresse réglée dans la console (réglage app.support_email).
Future<void> contactSupport(BuildContext context, WidgetRef ref) async {
  final settings =
      ref.read(publicSettingsProvider).valueOrNull ?? const <String, dynamic>{};
  final email = settings['app.support_email'];
  if (email is! String || !email.contains('@')) {
    showMessage(context, tr('Contact indisponible pour le moment.'));
    return;
  }
  final ok = await launchUrl(Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': tr('Coupon Pro IA : demande d’aide')}));
  if (!ok && context.mounted) {
    showMessage(context, trf('Écrivez-nous à {0}', [email]));
  }
}

/// Plafond par pari (rappelé dans le simulateur) et budget mensuel (suivi dans le carnet, alerte à
/// 80 % puis à 100 %). Choisis et modifiables à tout moment par l'utilisateur.
class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = ref.watch(stakeLimitsProvider);
    final cur = currencyLabel(ref.watch(publicSettingsProvider).valueOrNull);
    final l = limits.valueOrNull ?? const StakeLimits();
    String show(int? v) => v == null ? tr('Aucun') : money(v, currency: cur);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(tr('Budget mensuel')),
            subtitle: Text(trf(
                '{0} · alerte à 80 % puis à 100 %', [show(l.monthlyBudget)])),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, l, monthly: true, cur: cur),
          ),
          ListTile(
            leading: const Icon(Icons.front_hand_outlined),
            title: Text(tr('Plafond par pari')),
            subtitle: Text(trf('{0} · rappelé dans le simulateur de mise',
                [show(l.stakeLimit)])),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, l, monthly: false, cur: cur),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(tr('Mon carnet de paris')),
            subtitle: Text(tr('Vos mises notées et votre bilan réel du mois')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.journal),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, StakeLimits l,
      {required bool monthly, required String cur}) async {
    final current = monthly ? l.monthlyBudget : l.stakeLimit;
    final controller = TextEditingController(text: current?.toString() ?? '');
    final result = await showDialog<(bool, int?)>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(monthly ? tr('Budget mensuel') : tr('Plafond par pari')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: tr('Montant'),
              suffixText: cur,
              helperText: tr('Au moins 100')),
        ),
        actions: [
          if (current != null)
            TextButton(
                onPressed: () => Navigator.pop(d, (true, null)),
                child: Text(tr('Retirer'))),
          TextButton(
              onPressed: () => Navigator.pop(d), child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(d, (true, parseStake(controller.text))),
              child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    final value = result.$2;
    if (value != null && value < 100) {
      showMessage(context, tr('Montant minimum : 100.'), error: true);
      return;
    }
    try {
      await ref.read(journalRepositoryProvider).saveLimits(StakeLimits(
            monthlyBudget: monthly ? value : l.monthlyBudget,
            stakeLimit: monthly ? l.stakeLimit : value,
          ));
      ref.invalidate(stakeLimitsProvider);
      if (context.mounted) showMessage(context, tr('Enregistré.'));
    } catch (_) {
      if (context.mounted) {
        showMessage(context, tr('Enregistrement impossible pour le moment.'),
            error: true);
      }
    }
  }
}
