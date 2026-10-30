import 'package:flutter/material.dart';

/// État honnête d'un module pas encore livré : aucune donnée fictive,
/// seulement ce qui arrive et dans quel lot.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({
    super.key,
    required this.icon,
    required this.title,
    required this.lot,
    required this.description,
    this.features = const [],
  });

  final IconData icon;
  final String title;
  final String lot;
  final String description;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 36, color: scheme.primary),
        ),
        const SizedBox(height: 20),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            label: Text('Prévu au $lot'),
            avatar: Icon(Icons.schedule, size: 16, color: scheme.secondary),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(height: 12),
        Text(description,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant)),
        if (features.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ce que ce module apportera',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final f in features)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                              child:
                                  Text(f, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
