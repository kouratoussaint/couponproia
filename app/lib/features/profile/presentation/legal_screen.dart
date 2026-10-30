import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../system/system_providers.dart';

/// Mentions de responsabilité (section 23 du cahier des charges).
/// Le texte vient de `app_settings.legal.disclaimers`, avec une copie locale hors ligne.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final disclaimers = ref.watch(disclaimersProvider).valueOrNull ?? fallbackDisclaimers;
    return Scaffold(
      appBar: AppBar(title: const Text('Mentions et avertissements')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Coupon Pro IA est une plateforme d’analyse et de création de contenus de pronostics. '
            'Elle ne place aucun pari et n’est liée à aucun bookmaker.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final d in disclaimers)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.info_outline, color: theme.colorScheme.secondary),
                      title: Text(d),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Conditions générales d’utilisation et politique de confidentialité : en cours de rédaction, '
            'elles seront publiées avant l’ouverture au public.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
