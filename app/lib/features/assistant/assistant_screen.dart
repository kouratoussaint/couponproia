import 'package:flutter/material.dart';

import '../../core/widgets/coming_soon_view.dart';

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant IA')),
      body: const ComingSoonView(
        icon: Icons.smart_toy,
        title: 'Mon Assistant IA',
        lot: 'LOT 5',
        description: 'Décrivez le coupon que vous voulez en langage naturel ; l’IA le construit à partir '
            'de données réelles, le serveur le vérifie, et vous gardez la main.',
        features: [
          '« Fais-moi un coupon de 5 matchs avec une cote proche de 10 »',
          'Analyse et optimisation d’un coupon existant',
          'Comparaison de plusieurs propositions',
          'Laboratoire IA et générateur manuel (LOT 6)',
        ],
      ),
    );
  }
}
