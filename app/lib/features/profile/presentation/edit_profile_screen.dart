import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../onboarding/data/preferences_repository.dart';
import '../../onboarding/presentation/onboarding_sheet.dart';
import '../data/profile_repository.dart';

/// Pays proposés (code ISO à 2 lettres).
const profileCountries = <String, String>{
  'BF': 'Burkina Faso',
  'BJ': 'Bénin',
  'CI': 'Côte d’Ivoire',
  'CM': 'Cameroun',
  'CD': 'RD Congo',
  'CG': 'Congo',
  'GA': 'Gabon',
  'GH': 'Ghana',
  'GN': 'Guinée',
  'ML': 'Mali',
  'MR': 'Mauritanie',
  'NE': 'Niger',
  'NG': 'Nigeria',
  'SN': 'Sénégal',
  'TD': 'Tchad',
  'TG': 'Togo',
  'MA': 'Maroc',
  'DZ': 'Algérie',
  'TN': 'Tunisie',
  'FR': 'France',
  'BE': 'Belgique',
  'CH': 'Suisse',
  'CA': 'Canada',
};

/// Fuseaux horaires proposés (heure des matchs et des notifications).
const profileTimezones = <String, String>{
  'Africa/Ouagadougou': 'Ouagadougou, Abidjan, Dakar, Bamako (GMT)',
  'Africa/Lagos': 'Lagos, Douala, Niamey, Kinshasa (GMT+1)',
  'Africa/Casablanca': 'Casablanca (GMT+1)',
  'Europe/Paris': 'Paris, Bruxelles, Genève (heure d’Europe centrale)',
  'America/Toronto': 'Montréal, Toronto (heure de l’Est)',
};

/// Profil → crayon : toutes les informations du compte au même endroit.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _country = 'BF';
  String _timezone = 'Africa/Ouagadougou';
  String? _avatar;
  UserLevel? _level;
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _load(Profile p, UserPreferences? prefs) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.displayName;
    _country =
        profileCountries.containsKey(p.countryCode) ? p.countryCode : 'BF';
    _timezone = profileTimezones.containsKey(p.timezone)
        ? p.timezone
        : 'Africa/Ouagadougou';
    _avatar = p.avatarUrl;
    _level = prefs?.level;
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Image trop lourde (1 Mo maximum).');
      }
      final url = await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(bytes, file.name.split('.').last);
      setState(() => _avatar = url);
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is FormatException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.updateProfile(
        displayName: _name.text,
        countryCode: _country,
        timezone: _timezone,
        avatarUrl: _avatar,
      );
      if (_level != null) {
        await ref.read(preferencesRepositoryProvider).save(level: _level);
      }
      // Ménage des anciennes photos : sans effet sur l'enregistrement s'il échoue.
      try {
        await repo.cleanAvatars(_avatar);
      } catch (_) {}
      ref.invalidate(myProfileProvider);
      ref.invalidate(myPreferencesProvider);
      if (mounted) {
        showMessage(context, 'Profil enregistré.');
        context.pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref.watch(myProfileProvider);
    final prefs = ref.watch(myPreferencesProvider).valueOrNull;
    final email = ref.watch(currentUserProvider)?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le profil')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userMessageFor(e))),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          _load(p, prefs);
          return Form(
            key: _key,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: scheme.primary.withValues(alpha: 0.15),
                        foregroundImage:
                            _avatar == null ? null : NetworkImage(_avatar!),
                        child: Text(p.initials,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(color: scheme.primary)),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: IconButton.filled(
                          tooltip: 'Changer la photo',
                          onPressed: _busy ? null : _pickPhoto,
                          icon:
                              const Icon(Icons.photo_camera_outlined, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_avatar != null)
                  Center(
                    child: TextButton(
                      onPressed:
                          _busy ? null : () => setState(() => _avatar = null),
                      child: const Text('Retirer la photo'),
                    ),
                  ),
                const SizedBox(height: 12),
                const _Section('Identité'),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Pseudo'),
                  textInputAction: TextInputAction.next,
                  validator: Validators.displayName,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pays'),
                  items: [
                    for (final e in profileCountries.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _country = v ?? _country),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _timezone,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Fuseau horaire',
                      helperText:
                          'Heure des matchs, des notifications et des heures calmes'),
                  items: [
                    for (final e in profileTimezones.entries)
                      DropdownMenuItem(
                          value: e.key,
                          child:
                              Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _timezone = v ?? _timezone),
                ),
                const SizedBox(height: 20),
                const _Section('Mon niveau'),
                SegmentedButton<UserLevel>(
                  emptySelectionAllowed: true,
                  segments: [
                    for (final l in UserLevel.values)
                      ButtonSegment(value: l, label: Text(l.label)),
                  ],
                  selected: {if (_level != null) _level!},
                  onSelectionChanged: (s) =>
                      setState(() => _level = s.isEmpty ? _level : s.first),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('Compétitions suivies'),
                  subtitle: Text(() {
                    final n = prefs?.favoriteCompetitions.length ?? 0;
                    return n == 0
                        ? 'Aucune'
                        : '$n compétition${n > 1 ? 's' : ''}';
                  }()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showOnboarding(context, fromProfile: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Équipes suivies'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.favoriteTeams),
                ),
                const SizedBox(height: 12),
                const _Section('Connexion'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alternate_email),
                  title: const Text('Adresse e-mail'),
                  subtitle: Text(email),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changeEmail(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Mot de passe'),
                  subtitle: const Text('Changer le mot de passe'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changePassword(context),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enregistrer'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _changeEmail(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmailChangeSheet(),
    );
    if (changed == true && context.mounted) {
      showMessage(context, 'Adresse e-mail modifiée.');
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PasswordChangeSheet(),
    );
    if (changed == true && context.mounted) {
      showMessage(context, 'Mot de passe modifié.');
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Changement d'adresse : mot de passe actuel, nouvelle adresse, puis code reçu sur celle-ci.
class _EmailChangeSheet extends ConsumerStatefulWidget {
  const _EmailChangeSheet();

  @override
  ConsumerState<_EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends ConsumerState<_EmailChangeSheet> {
  final _key = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(profileRepositoryProvider);
    try {
      if (!_codeSent) {
        await repo.verifyPassword(_password.text);
        await repo.requestEmailChange(_email.text);
        setState(() => _codeSent = true);
      } else {
        await repo.confirmEmailChange(_email.text, _code.text);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Changer d’adresse e-mail',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!_codeSent) ...[
              PasswordField(
                controller: _password,
                label: 'Mot de passe actuel',
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Saisissez votre mot de passe.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(labelText: 'Nouvelle adresse e-mail'),
                validator: Validators.email,
              ),
            ] else ...[
              Text(
                  'Un code à 6 chiffres a été envoyé à ${_email.text.trim()} (pensez aux spams).'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Code reçu'),
                validator: Validators.otpCode,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_codeSent ? 'Confirmer' : 'Recevoir un code'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Changement de mot de passe : mot de passe actuel, puis le nouveau deux fois.
class _PasswordChangeSheet extends ConsumerStatefulWidget {
  const _PasswordChangeSheet();

  @override
  ConsumerState<_PasswordChangeSheet> createState() =>
      _PasswordChangeSheetState();
}

class _PasswordChangeSheetState extends ConsumerState<_PasswordChangeSheet> {
  final _key = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.verifyPassword(_current.text);
      await repo.changePassword(_next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Changer le mot de passe',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            PasswordField(
              controller: _current,
              label: 'Mot de passe actuel',
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Saisissez votre mot de passe.' : null,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _next,
              label: 'Nouveau mot de passe',
              textInputAction: TextInputAction.next,
              validator: Validators.password,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              label: 'Confirmer le nouveau mot de passe',
              validator: (v) => v != _next.text
                  ? 'Les mots de passe ne correspondent pas.'
                  : null,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Changer le mot de passe'),
            ),
          ],
        ),
      ),
    );
  }
}
