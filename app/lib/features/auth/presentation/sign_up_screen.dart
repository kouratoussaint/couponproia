import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../data/auth_repository.dart';

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
    if (!_adult || !_acceptedTerms) {
      showMessage(context, 'Cochez les deux cases pour continuer.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final needsCode = await ref.read(authRepositoryProvider).signUp(
            email: _email.text,
            password: _password.text,
            displayName: _name.text,
          );
      if (!mounted) return;
      if (needsCode) context.go(AppRoutes.verifyEmailFor(_email.text.trim()));
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      title: 'Créer un compte',
      subtitle: 'Gratuit. Un code de confirmation vous sera envoyé par email.',
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
                decoration: const InputDecoration(
                  labelText: 'Nom affiché',
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
                decoration: const InputDecoration(
                  labelText: 'Email',
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
                label: 'Confirmer le mot de passe',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v != _password.text
                    ? 'Les mots de passe ne correspondent pas.'
                    : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _adult,
                onChanged: (v) => setState(() => _adult = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('J’ai 18 ans ou plus.'),
              ),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Je comprends que les pronostics sont des estimations et qu’aucun gain n’est garanti.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              BusyButton(
                  label: 'Créer mon compte', busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
