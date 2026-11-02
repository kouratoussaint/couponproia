import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/brand_colors.dart';
import '../../core/theme/solid_buttons.dart';
import '../../core/widgets/app_logo.dart';
import '../assistant/data/assistant_models.dart';
import '../assistant/data/assistant_repository.dart';
import '../auth/data/auth_repository.dart';
import '../billing/credit_costs.dart';
import '../notifications/data/push_service.dart';
import '../profile/presentation/responsible_gaming_screen.dart';
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

/// Menu latéral : en-tête (forfait et crédits), puis Mon espace et compte, Découvrir,
/// Outils, Aide, Administration (équipe seulement) et déconnexion.
/// Les entrées qui correspondent à un onglet (Mes coupons, Laboratoire, Compétitions)
/// ouvrent directement cet onglet, sans écran en double.
class AppDrawer extends ConsumerWidget {
  const AppDrawer(
      {super.key, required this.currentIndex, required this.onSelectTab});

  final int currentIndex;
  final ValueChanged<int> onSelectTab;

  void _close() => shellScaffoldKey.currentState?.closeDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final version = ref.watch(installedPackageProvider).valueOrNull;

    void open(String location) {
      _close();
      context.push(location);
    }

    void go(String location) {
      _close();
      context.go(location);
    }

    void tab(int index) {
      _close();
      onSelectTab(index);
    }

    Widget item(IconData icon, String label, VoidCallback onTap,
            {bool selected = false}) =>
        Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Icon(icon),
            title: Text(label),
            selected: selected,
            onTap: onTap,
          ),
        );

    final team = permissions.contains('admin.access') ||
        permissions.contains('sports.configure') ||
        permissions.contains('ai.configure') ||
        permissions.contains('generation.manage');

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            DrawerHeaderCard(onTap: () => open(AppRoutes.billing)),
            const DrawerSectionTitle('Mon espace et compte'),
            item(Icons.bookmarks_outlined, 'Mes coupons',
                () => go(AppRoutes.assistantMyCoupons)),
            item(Icons.menu_book_outlined, 'Mon carnet de paris',
                () => open(AppRoutes.journal)),
            item(Icons.workspace_premium_outlined, 'Abonnement et crédits',
                () => open(AppRoutes.billing)),
            item(Icons.person_outline, 'Mon profil', () => tab(4),
                selected: currentIndex == 4),
            const Divider(),
            const DrawerSectionTitle('Découvrir'),
            item(Icons.home_outlined, 'Accueil', () => tab(0),
                selected: currentIndex == 0),
            item(Icons.sports_soccer_outlined, 'Matchs', () => tab(1),
                selected: currentIndex == 1),
            item(Icons.emoji_events_outlined, 'Compétitions et classements',
                () => go(AppRoutes.matchesCompetitions)),
            item(Icons.receipt_long_outlined, 'Coupons IA', () => tab(2),
                selected: currentIndex == 2),
            item(Icons.insights_outlined, 'Performances',
                () => open(AppRoutes.performance)),
            item(Icons.forum_outlined, 'Communauté et Tipsters',
                () => open(AppRoutes.community)),
            const Divider(),
            const DrawerSectionTitle('Outils'),
            item(Icons.smart_toy_outlined, 'Assistant IA', () => tab(3),
                selected: currentIndex == 3),
            item(Icons.science_outlined, 'Laboratoire IA',
                () => go(AppRoutes.assistantLab)),
            item(Icons.palette_outlined, 'Studio graphique',
                () => open(AppRoutes.studio)),
            const Divider(),
            const DrawerSectionTitle('Aide'),
            item(Icons.health_and_safety_outlined, 'Jeu responsable',
                () => open(AppRoutes.responsibleGaming)),
            item(Icons.support_agent, 'Contacter le support', () {
              _close();
              contactSupport(context, ref);
            }),
            item(Icons.gavel_outlined, 'Mentions légales et documents',
                () => go(AppRoutes.legal)),
            if (team) ...[
              const Divider(),
              const DrawerSectionTitle('Administration'),
              if (permissions.contains('admin.access'))
                item(
                    Icons.admin_panel_settings_outlined,
                    'Console d’administration',
                    () => open(AppRoutes.adminConsole)),
              if (!permissions.contains('admin.access') &&
                  permissions.contains('sports.configure'))
                item(Icons.sync_alt, 'Données sportives',
                    () => open(AppRoutes.sportsAdmin)),
              if (!permissions.contains('admin.access') &&
                  permissions.contains('generation.manage'))
                item(Icons.auto_mode, 'Coupons et générations',
                    () => open(AppRoutes.generationsAdmin)),
              if (!permissions.contains('admin.access') &&
                  permissions.contains('ai.configure'))
                item(Icons.psychology_outlined, 'Moteur et IA',
                    () => open(AppRoutes.engineAdmin)),
            ],
            const Divider(),
            Builder(builder: (context) {
              final red = theme.brightness == Brightness.dark
                  ? theme.colorScheme.error
                  : solidColors(context, SolidTone.red).bg;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(Icons.logout, color: red),
                title: Text('Se déconnecter',
                    style: TextStyle(color: red, fontWeight: FontWeight.w700)),
                onTap: () async {
                  _close();
                  await ref.read(pushServiceProvider).stop();
                  await ref.read(authRepositoryProvider).signOut();
                },
              );
            }),
            if (version != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  'Version ${version.version} (${version.buildNumber})',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// « Forfait PRO », « Forfait STARTER », « Compte équipe ».
String planBadge(Credits? c) {
  if (c == null) return '';
  if (c.unlimited) return 'Compte équipe';
  return 'Forfait ${c.plan.replaceAll('_', ' ')}';
}

/// « 50 crédits », « Illimités ».
String creditsBadge(Credits? c) {
  if (c == null) return '…';
  if (c.unlimited) return 'Illimités';
  return creditsLabel(c.total);
}

/// En-tête du menu : application, compte, forfait réel et solde de crédits.
/// Au forfait FREE, un bouton « Voir les forfaits ». Un toucher ouvre Abonnement et crédits.
class DrawerHeaderCard extends ConsumerWidget {
  const DrawerHeaderCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final credits = ref.watch(myCreditsProvider).valueOrNull;
    const fg = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.75);
    final isFree =
        credits != null && !credits.unlimited && credits.plan == 'FREE';
    return Card(
      color: BrandColors.vertProfond,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: theme.brightness == Brightness.dark
            ? const BorderSide(color: BrandColors.bordureSombre)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const AppLogo(size: 44, showName: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Coupon Pro IA',
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: fg, fontWeight: FontWeight.w800)),
                      Text('Espace utilisateur',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: BrandColors.vertIA.withValues(alpha: 0.25),
                  foregroundImage: profile?.avatarUrl == null
                      ? null
                      : NetworkImage(profile!.avatarUrl!),
                  child: Text(profile?.initials ?? '?',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: BrandColors.vertIA)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.displayName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: fg, fontWeight: FontWeight.w700)),
                      Text(planBadge(credits),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text('Crédits IA disponibles',
                        style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
                  ),
                  Text(creditsBadge(credits),
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: BrandColors.vertIA,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
              if (isFree) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: solidButtonStyle(context, SolidTone.green),
                  onPressed: onTap,
                  icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: const Text('Voir les forfaits'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Titre de section du menu (« MON ESPACE ET COMPTE »…).
class DrawerSectionTitle extends StatelessWidget {
  const DrawerSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6),
      ),
    );
  }
}
