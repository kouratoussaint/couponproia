import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
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
