import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_logo.dart';
import '../profile/data/profile_repository.dart';
import '../system/system_providers.dart';

/// Modules affichés sur l'accueil avec leur lot de livraison et leur flag.
const _modules = [
  (flag: 'match_analysis', title: 'Matchs et analyses IA', lot: 'LOTS 2-3', icon: Icons.sports_soccer),
  (flag: 'auto_generation_scheduled', title: 'Coupons IA de la plateforme', lot: 'LOT 4', icon: Icons.receipt_long),
  (flag: 'assistant_ia', title: 'Mon Assistant IA', lot: 'LOT 5', icon: Icons.smart_toy),
  (flag: 'ai_lab', title: 'Laboratoire IA', lot: 'LOT 6', icon: Icons.science),
  (flag: 'results_tracking', title: 'Suivi des performances', lot: 'LOT 8', icon: Icons.insights),
  (flag: 'subscriptions', title: 'Forfaits et crédits IA', lot: 'LOT 9', icon: Icons.workspace_premium),
];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = ref.watch(myProfileProvider).valueOrNull?.displayName;
    final flags = ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};

    return Scaffold(
      appBar: AppBar(title: const AppLogo(size: 30)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(featureFlagsProvider);
          ref.invalidate(myProfileProvider);
          await ref.read(featureFlagsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              name == null ? 'Bonjour' : 'Bonjour, $name',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'L’intelligence au service de vos pronostics.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Card(
              color: scheme.primary.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.rocket_launch_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Version de fondation (LOT 1) : compte, profil et thèmes sont en place. '
                        'Les modules d’analyse arrivent lot par lot ; aucune donnée affichée ici n’est fictive.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Modules', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final m in _modules)
                    ListTile(
                      leading: Icon(m.icon, color: scheme.primary),
                      title: Text(m.title),
                      subtitle: Text(m.lot),
                      trailing: (flags[m.flag] ?? false)
                          ? Chip(
                              label: const Text('Actif'),
                              backgroundColor: scheme.primary.withValues(alpha: 0.15),
                              side: BorderSide.none,
                            )
                          : const Chip(label: Text('Bientôt')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Les pronostics sont des estimations. Aucun gain n’est garanti.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
