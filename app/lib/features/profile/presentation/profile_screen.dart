import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/text_scale_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../billing/billing_repository.dart';
import '../../notifications/data/push_service.dart';
import '../../onboarding/data/preferences_repository.dart';
import '../../onboarding/presentation/onboarding_sheet.dart';
import 'responsible_gaming_screen.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../system/system_providers.dart';
import '../data/profile_repository.dart';
import '../../shell/app_drawer.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider);
    final user = ref.watch(currentUserProvider);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    final themeMode = ref.watch(themeModeProvider);
    final version = ref.watch(installedPackageProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
          leading: const DrawerMenuButton(), title: const Text('Profil')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myProfileProvider);
          ref.invalidate(myPermissionsProvider);
          await ref.read(myProfileProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: profile.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(userMessageFor(e)),
                  data: (p) => Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        foregroundImage: p?.avatarUrl == null
                            ? null
                            : NetworkImage(p!.avatarUrl!),
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Text(
                          p?.initials ?? '?',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p?.displayName ?? '—',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Modifier le profil',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: p == null
                            ? null
                            : () => context.push(AppRoutes.profileEdit),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Mes préférences'),
                    subtitle: Text(() {
                      final p = ref.watch(myPreferencesProvider).valueOrNull;
                      final n = p?.favoriteCompetitions.length ?? 0;
                      return [
                        n == 0
                            ? 'Aucune compétition suivie'
                            : '$n compétition${n > 1 ? 's' : ''} suivie${n > 1 ? 's' : ''}',
                        if (p?.level != null)
                          'niveau ${p!.level!.label.toLowerCase()}',
                      ].join(' · ');
                    }()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showOnboarding(context, fromProfile: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_none),
                    title: const Text('Notifications'),
                    subtitle: const Text('Ce que je reçois, heures calmes'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.notificationSettings),
                  ),
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Équipes suivies'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.favoriteTeams),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('Mon profil Tipster'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.myTipsterProfile),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block),
                    title: const Text('Utilisateurs bloqués'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.blockedUsers),
                  ),
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('Abonnement'),
                    subtitle: Text(
                      ref.watch(entitlementsProvider).when(
                            data: (e) => e.periodEnd == null
                                ? 'Forfait ${e.plan.replaceAll('_', ' ')}'
                                : 'Forfait ${e.plan.replaceAll('_', ' ')} · jusqu’au ${e.periodEnd!.day.toString().padLeft(2, '0')}/${e.periodEnd!.month.toString().padLeft(2, '0')}/${e.periodEnd!.year}',
                            loading: () => '…',
                            error: (_, __) => 'Forfait indisponible',
                          ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.billing),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bolt),
                    title: const Text('Crédits IA'),
                    subtitle: Text(
                      ref.watch(myCreditsProvider).when(
                            data: (c) => c.unlimited
                                ? 'Illimités (compte équipe)'
                                : '${c.total} disponible(s) · ${c.planCredits} du forfait ce mois-ci + ${c.extraCredits} supplémentaire(s)',
                            loading: () => '…',
                            error: (_, __) => 'Solde indisponible',
                          ),
                    ),
                  ),
                  if (permissions.contains('admin.access'))
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Console d’administration'),
                      subtitle: const Text(
                          'Utilisateurs, coupons, paiements, réglages'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.adminConsole),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Apparence', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Système'),
                            icon: Icon(Icons.brightness_auto_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Clair'),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Sombre'),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) => ref
                            .read(themeModeProvider.notifier)
                            .setMode(s.first),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Taille du texte', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<TextSize>(
                        showSelectedIcon: false,
                        segments: [
                          for (final t in TextSize.values)
                            ButtonSegment(
                              value: t,
                              label: Text('A',
                                  style: TextStyle(
                                      fontSize: 14 * t.factor,
                                      fontWeight: FontWeight.w700)),
                              tooltip: t.label,
                            ),
                        ],
                        selected: {ref.watch(textSizeProvider)},
                        onSelectionChanged: (s) =>
                            ref.read(textSizeProvider.notifier).set(s.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${ref.watch(textSizeProvider).label} : voici à quoi ressemble le texte de l’app.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.support_agent),
                    title: const Text('Contacter le support'),
                    subtitle: const Text(
                        'Signaler un problème ou poser une question'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => contactSupport(context, ref),
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('Mon carnet de paris'),
                    subtitle:
                        const Text('Vos mises notées et votre bilan réel'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.journal),
                  ),
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: const Text('Jeu responsable'),
                    subtitle: const Text(
                        'Budget mensuel, plafond par pari, conseils'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.responsibleGaming),
                  ),
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Conditions et mentions'),
                    subtitle: const Text(
                        'CGU, confidentialité, règles de la communauté, avertissements'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.legal),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Se déconnecter'),
                    onTap: () async {
                      await ref.read(pushServiceProvider).stop();
                      await ref.read(authRepositoryProvider).signOut();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined,
                        color: theme.colorScheme.error),
                    title: Text('Supprimer mon compte',
                        style: TextStyle(color: theme.colorScheme.error)),
                    onTap: () => _confirmDeletion(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                version == null
                    ? ''
                    : 'Version ${version.version} (${version.buildNumber})',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletion(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      if (context.mounted) showMessage(context, 'Votre compte a été supprimé.');
    } catch (e) {
      if (context.mounted) showMessage(context, userMessageFor(e), error: true);
    }
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim() == 'SUPPRIMER';
    return AlertDialog(
      title: const Text('Supprimer mon compte ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Votre profil, vos préférences et votre historique seront effacés définitivement. '
            'Cette action est irréversible.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Tapez SUPPRIMER pour confirmer'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            minimumSize: const Size(0, 44),
          ),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Supprimer'),
        ),
      ],
    );
  }
}
