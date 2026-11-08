import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../legal/legal_repository.dart';
import '../../legal/legal_screens.dart';
import '../data/auth_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _adult = false;
  bool _acceptedTerms = false;
  bool _acceptedLegal = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_adult || !_acceptedTerms || !_acceptedLegal) {
      showMessage(context, tr('Cochez les trois cases pour continuer.'),
          error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _rememberAcceptedVersions();
      final needsCode = await ref.read(authRepositoryProvider).signUp(
            email: _email.text,
            password: _password.text,
            displayName: _name.text,
          );
      if (!mounted) return;
      if (needsCode) context.push(AppRoutes.verifyEmailFor(_email.text.trim()));
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Versions lues et acceptées ici : enregistrées à la première connexion (pas de seconde demande).
  Future<void> _rememberAcceptedVersions() async {
    try {
      final docs = await Future.wait([
        ref.read(legalDocumentProvider('terms').future),
        ref.read(legalDocumentProvider('privacy').future),
      ]);
      final ids = [
        for (final d in docs)
          if (d != null) d.id
      ];
      if (ids.length == 2) {
        await ref
            .read(sharedPreferencesProvider)
            .setString(legalSignupKey, ids.join(','));
      }
    } catch (_) {
      // Hors ligne : l'acceptation sera demandée à la première connexion.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      title: tr('Créer un compte'),
      subtitle:
          tr('Gratuit. Un code de confirmation vous sera envoyé par e-mail.'),
      showBack: true,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.nickname],
                textInputAction: TextInputAction.next,
                validator: Validators.displayName,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: tr('Nom affiché'),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: Validators.email,
                decoration: InputDecoration(
                  labelText: tr('Adresse e-mail'),
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                validator: Validators.password,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: tr('Confirmer le mot de passe'),
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v != _password.text
                    ? tr('Les mots de passe ne correspondent pas.')
                    : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _adult,
                onChanged: (v) => setState(() => _adult = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr('J’ai 18 ans ou plus.')),
              ),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  tr('Je comprends que les pronostics sont des estimations et qu’aucun gain n’est garanti.'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              CheckboxListTile(
                value: _acceptedLegal,
                onChanged: (v) => setState(() => _acceptedLegal = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const LegalConsentText(withAge: false),
              ),
              const SizedBox(height: 16),
              BusyButton(
                  label: tr('Créer mon compte'),
                  busy: _busy,
                  onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
