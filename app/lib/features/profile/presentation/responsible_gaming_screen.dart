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

/// Jeu responsable : repères simples, sans jugement, et outils disponibles dans l'app.
class ResponsibleGamingScreen extends StatelessWidget {
  const ResponsibleGamingScreen({super.key});

  static const _tips = [
    (
      'Fixez un budget',
      'Décidez à l’avance d’une somme que vous pouvez perdre sans conséquence, et arrêtez-vous quand elle est atteinte.'
    ),
    (
      'Ne courez pas après vos pertes',
      'Augmenter les mises pour « se refaire » mène presque toujours à des pertes plus grandes.'
    ),
    (
      'Pas d’argent nécessaire',
      'Ne pariez jamais l’argent du loyer, de la nourriture, de l’école ou des dettes.'
    ),
    (
      'Faites des pauses',
      'Le football reste un plaisir : prenez des jours sans paris.'
    ),
    (
      'Gardez l’esprit critique',
      'Nos chiffres sont des estimations. Un coupon peut perdre même quand l’analyse est juste.'
    ),
  ];

  static const _signs = [
    'Vous pariez plus que prévu, ou de plus en plus souvent.',
    'Vous cachez vos paris à vos proches.',
    'Vous empruntez ou vendez des biens pour parier.',
    'Le jeu vous rend nerveux, irritable ou vous empêche de dormir.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Jeu responsable')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Coupon Pro IA propose des analyses et des estimations. Nous ne prenons aucun pari et aucun gain '
            'n’est garanti. Les paris sportifs sont interdits aux moins de 18 ans.',
            style: theme.textTheme.bodyLarge,
          ),
          const SectionTitle('Mon budget'),
          const BudgetCard(),
          const SectionTitle('Bonnes pratiques'),
          for (final (title, text) in _tips)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(title),
                    subtitle: Text(text))),
          const SectionTitle('Signes d’alerte'),
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
                    'Si vous vous reconnaissez, parlez-en à un proche ou à un professionnel de santé. Demander de l’aide '
                    'est une bonne décision.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Dans l’app'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('Couper les notifications'),
                  subtitle:
                      const Text('Toutes, ou seulement les nouveaux coupons'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Supprimer mon compte'),
                  subtitle: const Text('Depuis l’écran Profil, à tout moment'),
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
    showMessage(context, 'Contact indisponible pour le moment.');
    return;
  }
  final ok = await launchUrl(Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Coupon Pro IA : demande d’aide'}));
  if (!ok && context.mounted) showMessage(context, 'Écrivez-nous à $email');
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
    String show(int? v) => v == null ? 'Aucun' : money(v, currency: cur);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Budget mensuel'),
            subtitle:
                Text('${show(l.monthlyBudget)} · alerte à 80 % puis à 100 %'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, l, monthly: true, cur: cur),
          ),
          ListTile(
            leading: const Icon(Icons.front_hand_outlined),
            title: const Text('Plafond par pari'),
            subtitle: Text(
                '${show(l.stakeLimit)} · rappelé dans le simulateur de mise'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, l, monthly: false, cur: cur),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Mon carnet de paris'),
            subtitle:
                const Text('Vos mises notées et votre bilan réel du mois'),
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
        title: Text(monthly ? 'Budget mensuel' : 'Plafond par pari'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: 'Montant',
              suffixText: cur,
              helperText: 'Au moins 100'),
        ),
        actions: [
          if (current != null)
            TextButton(
                onPressed: () => Navigator.pop(d, (true, null)),
                child: const Text('Retirer')),
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(d, (true, parseStake(controller.text))),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    final value = result.$2;
    if (value != null && value < 100) {
      showMessage(context, 'Montant minimum : 100.', error: true);
      return;
    }
    try {
      await ref.read(journalRepositoryProvider).saveLimits(StakeLimits(
            monthlyBudget: monthly ? value : l.monthlyBudget,
            stakeLimit: monthly ? l.stakeLimit : value,
          ));
      ref.invalidate(stakeLimitsProvider);
      if (context.mounted) showMessage(context, 'Enregistré.');
    } catch (_) {
      if (context.mounted) {
        showMessage(context, 'Enregistrement impossible pour le moment.',
            error: true);
      }
    }
  }
}
