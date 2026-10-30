import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../data/auth_repository.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  bool _resending = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmSignUp(email: widget.email, code: _code.text);
      // Session ouverte : le routeur redirige vers l'accueil.
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(authRepositoryProvider).resendSignUpCode(widget.email);
      if (mounted) {
        showMessage(context, 'Nouveau code envoyé à ${widget.email}.');
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingEmail = widget.email.isEmpty;
    return AuthScaffold(
      title: 'Confirmez votre email',
      subtitle: missingEmail
          ? 'Adresse inconnue : recommencez depuis la connexion.'
          : 'Saisissez le code à 6 chiffres envoyé à ${widget.email} (pensez aux spams). '
              'Si l’email contient un lien au lieu d’un code, ouvrez-le, puis revenez vous connecter.',
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
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(letterSpacing: 8),
              decoration:
                  const InputDecoration(labelText: 'Code de confirmation'),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            BusyButton(
                label: 'Confirmer',
                busy: _busy,
                onPressed: missingEmail ? null : _submit),
            const SizedBox(height: 12),
            TextButton(
              onPressed: missingEmail || _resending ? null : _resend,
              child: Text(_resending ? 'Envoi…' : 'Renvoyer le code'),
            ),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.signIn),
              child: const Text('J’ai confirmé par le lien : me connecter'),
            ),
          ],
        ),
      ),
    );
  }
}
