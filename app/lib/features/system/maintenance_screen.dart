import 'package:flutter/material.dart';

import '../../core/widgets/app_logo.dart';

/// Écran affiché quand l'administration active le flag `maintenance_mode`.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 40),
                const SizedBox(height: 32),
                Icon(Icons.construction_outlined,
                    size: 48, color: theme.colorScheme.secondary),
                const SizedBox(height: 16),
                Text('Maintenance en cours',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Coupon Pro IA est momentanément indisponible. Réessayez dans quelques minutes.',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                    onPressed: onRetry, child: const Text('Réessayer')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
