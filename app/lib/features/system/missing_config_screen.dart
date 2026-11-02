import 'package:flutter/material.dart';

import '../../core/widgets/app_logo.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Affiché quand l'APK a été compilé sans URL ni clé Supabase.
class MissingConfigScreen extends StatelessWidget {
  const MissingConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(size: 40),
              const Spacer(),
              Icon(Icons.settings_suggest_outlined,
                  size: 48, color: theme.colorScheme.secondary),
              const SizedBox(height: 16),
              Text(tr('Configuration serveur manquante'),
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                tr('Cette version a été compilée sans l’adresse du serveur Supabase. Elle permet de vérifier l’installation et l’interface, mais pas de se connecter. Installez une version compilée avec SUPABASE_URL et SUPABASE_ANON_KEY.'),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
