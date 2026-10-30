import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../auth/data/auth_repository.dart';
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
                        tooltip: 'Modifier le nom',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: p == null
                            ? null
                            : () => _editName(context, ref, p.displayName),
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
                  const ListTile(
                    leading: Icon(Icons.workspace_premium_outlined),
                    title: Text('Abonnement'),
                    subtitle: Text('FREE · les forfaits arrivent au LOT 9'),
                  ),
                  if (permissions.contains('admin.access'))
                    const ListTile(
                      leading: Icon(Icons.admin_panel_settings_outlined),
                      title: Text('Administration'),
                      subtitle:
                          Text('Accès autorisé · console prévue au LOT 11'),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Mentions et avertissements'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.legal),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Se déconnecter'),
                    onTap: () => ref.read(authRepositoryProvider).signOut(),
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

  Future<void> _editName(
      BuildContext context, WidgetRef ref, String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditNameDialog(initial: current),
    );
    if (name == null || name.trim() == current || !context.mounted) return;
    try {
      await ref.read(profileRepositoryProvider).updateDisplayName(name);
      ref.invalidate(myProfileProvider);
      if (context.mounted) showMessage(context, 'Nom mis à jour.');
    } catch (e) {
      if (context.mounted) showMessage(context, userMessageFor(e), error: true);
    }
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

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initial});

  final String initial;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nom affiché'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          validator: Validators.displayName,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
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
