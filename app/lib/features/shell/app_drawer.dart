import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/app_logo.dart';
import '../auth/data/auth_repository.dart';
import '../profile/data/profile_repository.dart';
import '../system/system_providers.dart';

/// Clé du Scaffold principal : permet d'ouvrir le menu depuis la barre de chaque onglet.
final shellScaffoldKey = GlobalKey<ScaffoldState>();

/// Bouton « menu » à placer en tête des barres d'application des onglets.
class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
    );
  }
}

/// Menu latéral : les cinq espaces principaux, les espaces secondaires
/// (avec leur lot de livraison s'ils ne sont pas encore prêts) et l'administration.
class AppDrawer extends ConsumerWidget {
  const AppDrawer(
      {super.key, required this.currentIndex, required this.onSelectTab});

  final int currentIndex;
  final ValueChanged<int> onSelectTab;

  void _close() => shellScaffoldKey.currentState?.closeDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final user = ref.watch(currentUserProvider);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final version = ref.watch(installedPackageProvider).valueOrNull;

    void open(String location) {
      _close();
      context.push(location);
    }

    return NavigationDrawer(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) {
        _close();
        onSelectTab(index);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppFullLogo(height: 84),
              const SizedBox(height: 12),
              Text(profile?.displayName ?? '',
                  style: theme.textTheme.titleMedium),
              Text(
                user?.email ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(indent: 24, endIndent: 24),
        const NavigationDrawerDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Accueil'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.sports_soccer_outlined),
          selectedIcon: Icon(Icons.sports_soccer),
          label: Text('Matchs'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: Text('Coupons'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.smart_toy_outlined),
          selectedIcon: Icon(Icons.smart_toy),
          label: Text('Assistant IA'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profil'),
        ),
        const Divider(indent: 24, endIndent: 24),
        _SectionTitle('Explorer'),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.emoji_events_outlined),
          title: const Text('Compétitions et classements'),
          onTap: () => open(AppRoutes.competitions),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('Mes coupons'),
          onTap: () => open(AppRoutes.myCoupons),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.science_outlined),
          title: const Text('Laboratoire IA'),
          onTap: () => open(AppRoutes.lab),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.insights_outlined),
          title: const Text('Performances'),
          onTap: () => open(AppRoutes.performance),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Abonnement et crédits'),
          onTap: () => open(AppRoutes.billing),
        ),
        const _SoonTile(
            icon: Icons.palette_outlined,
            label: 'Studio graphique',
            lot: 'LOT 7'),
        if (permissions.contains('sports.configure') ||
            permissions.contains('ai.configure') ||
            permissions.contains('generation.manage')) ...[
          const Divider(indent: 24, endIndent: 24),
          _SectionTitle('Administration'),
          if (permissions.contains('sports.configure'))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 28),
              leading: const Icon(Icons.sync_alt),
              title: const Text('Données sportives'),
              onTap: () => open(AppRoutes.sportsAdmin),
            ),
          if (permissions.contains('generation.manage'))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 28),
              leading: const Icon(Icons.auto_mode),
              title: const Text('Générations de coupons'),
              onTap: () => open(AppRoutes.generationsAdmin),
            ),
          if (permissions.contains('ai.configure'))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 28),
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('Moteur d’analyse'),
              onTap: () => open(AppRoutes.engineAdmin),
            ),
        ],
        const Divider(indent: 24, endIndent: 24),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Mentions et avertissements'),
          onTap: () {
            _close();
            context.go(AppRoutes.legal);
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.logout),
          title: const Text('Se déconnecter'),
          onTap: () {
            _close();
            ref.read(authRepositoryProvider).signOut();
          },
        ),
        if (version != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            child: Text(
              'Version ${version.version} (${version.buildNumber})',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _SoonTile extends StatelessWidget {
  const _SoonTile({required this.icon, required this.label, required this.lot});

  final IconData icon;
  final String label;
  final String lot;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 28),
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(lot, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
