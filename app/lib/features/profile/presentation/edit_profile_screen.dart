import 'package:flutter/material.dart';
import 'package:coupon_pro_ia/core/widgets/unsaved_changes_guard.dart';
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
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Pays proposés (code ISO à 2 lettres).
final profileCountries = <String, String>{
  'BF': tr('Burkina Faso'),
  'BJ': tr('Bénin'),
  'CI': tr('Côte d’Ivoire'),
  'CM': tr('Cameroun'),
  'CD': tr('RD Congo'),
  'CG': tr('Congo'),
  'GA': tr('Gabon'),
  'GH': tr('Ghana'),
  'GN': tr('Guinée'),
  'ML': tr('Mali'),
  'MR': tr('Mauritanie'),
  'NE': tr('Niger'),
  'NG': tr('Nigeria'),
  'SN': tr('Sénégal'),
  'TD': tr('Tchad'),
  'TG': tr('Togo'),
  'MA': tr('Maroc'),
  'DZ': tr('Algérie'),
  'TN': tr('Tunisie'),
  'FR': tr('France'),
  'BE': tr('Belgique'),
  'CH': tr('Suisse'),
  'CA': tr('Canada'),
};

/// Fuseaux horaires proposés (heure des matchs et des notifications).
final profileTimezones = <String, String>{
  'Africa/Ouagadougou': tr('Ouagadougou, Abidjan, Dakar, Bamako (GMT)'),
  'Africa/Lagos': tr('Lagos, Douala, Niamey, Kinshasa (GMT+1)'),
  'Africa/Casablanca': tr('Casablanca (GMT+1)'),
  'Europe/Paris': tr('Paris, Bruxelles, Genève (heure d’Europe centrale)'),
  'America/Toronto': tr('Montréal, Toronto (heure de l’Est)'),
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

  /// Saisie au chargement, pour savoir si quelque chose a changé (lot 27).
  String? _baseline;
  String _signature() =>
      [_name.text, _country, _timezone, _avatar, _level?.name].join('\u0001');
  bool _dirty() => _baseline != null && _signature() != _baseline;

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
    _baseline = _signature();
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
        throw FormatException(tr('Image trop lourde (1 Mo maximum).'));
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
        showMessage(context, tr('Profil enregistré.'));
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
    return UnsavedChangesGuard(
        isDirty: _dirty,
        child: Scaffold(
          appBar: AppBar(title: Text(tr('Modifier le profil'))),
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
                            backgroundColor:
                                scheme.primary.withValues(alpha: 0.15),
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
                              tooltip: tr('Changer la photo'),
                              onPressed: _busy ? null : _pickPhoto,
                              icon: const Icon(Icons.photo_camera_outlined,
                                  size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_avatar != null)
                      Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _avatar = null),
                          child: Text(tr('Retirer la photo')),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _Section(tr('Identité')),
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(labelText: tr('Pseudo')),
                      textInputAction: TextInputAction.next,
                      validator: Validators.displayName,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _country,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Pays')),
                      items: [
                        for (final e in profileCountries.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) =>
                          setState(() => _country = v ?? _country),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _timezone,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: tr('Fuseau horaire'),
                          helperText: tr(
                              'Heure des matchs, des notifications et des heures calmes')),
                      items: [
                        for (final e in profileTimezones.entries)
                          DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) =>
                          setState(() => _timezone = v ?? _timezone),
                    ),
                    const SizedBox(height: 20),
                    _Section(tr('Mon niveau')),
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
                      title: Text(tr('Compétitions suivies')),
                      subtitle: Text(() {
                        final n = prefs?.favoriteCompetitions.length ?? 0;
                        return n == 0
                            ? tr('Aucune')
                            : trf('{0} compétition{1}', [n, n > 1 ? 's' : '']);
                      }()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showOnboarding(context, fromProfile: true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.star_outline),
                      title: Text(tr('Équipes suivies')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.favoriteTeams),
                    ),
                    const SizedBox(height: 12),
                    _Section(tr('Connexion')),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.alternate_email),
                      title: Text(tr('Adresse e-mail')),
                      subtitle: Text(email),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _changeEmail(context),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: Text('Mot de passe'),
                      subtitle: Text(tr('Changer le mot de passe')),
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
                          : Text(tr('Enregistrer')),
                    ),
                  ],
                ),
              );
            },
          ),
        ));
  }

  Future<void> _changeEmail(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmailChangeSheet(),
    );
    if (changed == true && context.mounted) {
      showMessage(context, tr('Adresse e-mail modifiée.'));
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
      showMessage(context, tr('Mot de passe modifié.'));
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
            Text(tr('Changer d’adresse e-mail'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!_codeSent) ...[
              PasswordField(
                controller: _password,
                label: tr('Mot de passe actuel'),
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').isEmpty
                    ? tr('Saisissez votre mot de passe.')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    InputDecoration(labelText: tr('Nouvelle adresse e-mail')),
                validator: Validators.email,
              ),
            ] else ...[
              Text(trf(
                  'Un code à 6 chiffres a été envoyé à {0} (pensez aux spams).',
                  [_email.text.trim()])),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(labelText: tr('Code reçu')),
                validator: Validators.otpCode,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_codeSent ? tr('Confirmer') : tr('Recevoir un code')),
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
            Text(tr('Changer le mot de passe'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            PasswordField(
              controller: _current,
              label: tr('Mot de passe actuel'),
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').isEmpty
                  ? tr('Saisissez votre mot de passe.')
                  : null,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _next,
              label: tr('Nouveau mot de passe'),
              textInputAction: TextInputAction.next,
              validator: Validators.password,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              label: tr('Confirmer le nouveau mot de passe'),
              validator: (v) => v != _next.text
                  ? tr('Les mots de passe ne correspondent pas.')
                  : null,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(tr('Changer le mot de passe')),
            ),
          ],
        ),
      ),
    );
  }
}
