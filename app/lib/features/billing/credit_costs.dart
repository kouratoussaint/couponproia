// Coût en crédits des actions payantes, réglé dans la console (réglages publics).
// Affichage seulement : le serveur applique toujours ses propres règles.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assistant/data/assistant_models.dart';
import '../system/system_providers.dart';

int _cost(Ref ref, String key) {
  final v = ref.watch(publicSettingsProvider).valueOrNull?[key];
  final n = v is num ? v.round() : int.tryParse('$v') ?? 1;
  return n < 0 ? 0 : n;
}

/// Analyse de match au forfait FREE.
final analysisCostProvider =
    Provider<int>((ref) => _cost(ref, 'analysis.credit_cost'));

/// Action payante de l'assistant (créer, modifier, analyser…), tous forfaits.
final assistantCostProvider = Provider<int>((ref) {
  final n = _cost(ref, 'assistant.cost_per_action');
  return n < 1 ? 1 : n;
});

/// Calcul du laboratoire (analyser, optimiser, comparer, simuler) au forfait FREE.
final labCostProvider = Provider<int>((ref) => _cost(ref, 'lab.credit_cost'));

/// « 1 crédit », « 3 crédits ».
String creditsLabel(int n) => '$n crédit${n > 1 ? 's' : ''}';

/// Le compte paie-t-il en crédits les actions réservées au FREE (analyse, laboratoire) ?
bool paysCreditsAsFree(Credits? c) =>
    c != null && !c.unlimited && c.plan == 'FREE';

/// Le compte paie-t-il en crédits les actions de l'assistant ?
bool paysCredits(Credits? c) => c != null && !c.unlimited;
