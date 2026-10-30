import 'package:flutter/material.dart';

import '../../core/widgets/coming_soon_view.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchs')),
      body: const ComingSoonView(
        icon: Icons.sports_soccer,
        title: 'Matchs et analyses',
        lot: 'LOT 2',
        description: 'Les rencontres réelles, synchronisées depuis le fournisseur de données sportives, '
            'avec leur source et l’heure de mise à jour.',
        features: [
          'Matchs du jour, de demain, en cours et terminés',
          'Fiche match : forme, confrontations, statistiques, cotes',
          'Bouton « Analyser avec l’IA » (LOT 3)',
          'Recherche par équipe et par compétition',
        ],
      ),
    );
  }
}
