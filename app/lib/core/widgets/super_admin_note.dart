import 'package:flutter/material.dart';

/// Encadré « visible par le super administrateur uniquement » : détails techniques
/// (fournisseur et modèle d'IA, version du moteur) que les utilisateurs ne voient pas.
class SuperAdminNote extends StatelessWidget {
  const SuperAdminNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Visible par le super administrateur uniquement',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
