import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../data/auth_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Étape 1 : demander un code de réinitialisation.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetCode(_email.text);
      if (!mounted) return;
      context.go(AppRoutes.resetPasswordFor(_email.text.trim()));
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: tr('Mot de passe oublié'),
      subtitle: tr(
          'Indiquez votre adresse e-mail : vous recevrez un code pour choisir un nouveau mot de passe.'),
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: Validators.email,
              decoration: InputDecoration(
                labelText: tr('Adresse e-mail'),
                prefixIcon: Icon(Icons.alternate_email),
              ),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            BusyButton(
                label: tr('Recevoir un code'), busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

/// Étape 2 : saisir le code et le nouveau mot de passe.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(
            email: widget.email,
            code: _code.text,
            newPassword: _password.text,
          );
      if (!mounted) return;
      showMessage(context, tr('Mot de passe modifié. Vous êtes connecté.'));
      context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingEmail = widget.email.isEmpty;
    return AuthScaffold(
      title: tr('Nouveau mot de passe'),
      subtitle: missingEmail
          ? tr('Adresse inconnue : recommencez depuis « Mot de passe oublié ».')
          : trf('Code envoyé à {0}. Il expire dans une heure.', [widget.email]),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _code,
                enabled: !missingEmail,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6)
                ],
                validator: Validators.otpCode,
                decoration: InputDecoration(
                  labelText: tr('Code reçu par e-mail'),
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                label: tr('Nouveau mot de passe'),
                validator: Validators.password,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: tr('Confirmer'),
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v != _password.text
                    ? tr('Les mots de passe ne correspondent pas.')
                    : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              BusyButton(
                  label: tr('Enregistrer'),
                  busy: _busy,
                  onPressed: missingEmail ? null : _submit),
              TextButton(
                onPressed: () => context.go(AppRoutes.signIn),
                child: Text(tr('Retour à la connexion')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
