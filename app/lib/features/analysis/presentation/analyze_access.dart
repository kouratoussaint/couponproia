import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/solid_buttons.dart';
import '../../assistant/data/assistant_models.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../billing/credit_costs.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/data/sports_models.dart';
import '../../matches/data/sports_repository.dart';
import '../../system/system_providers.dart';
import '../data/analysis_repository.dart';

/// Forfait payant, crédits suffisants ou compte de l'équipe : même règle que le serveur.
bool canAnalyzeWith(Credits? c, {int cost = 1}) =>
    c != null &&
    (c.unlimited || c.plan != 'FREE' || cost <= 0 || c.total >= cost);

/// Ce compte peut-il lancer l'analyse de ce match ? L'analyse offerte du jour reste ouverte.
final analysisAllowedProvider =
    Provider.autoDispose.family<bool, int>((ref, matchId) {
  final perms =
      ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
  if (perms.contains('ai.configure')) return true;
  if (ref.watch(featuredMatchProvider).valueOrNull == matchId) return true;
  return canAnalyzeWith(ref.watch(myCreditsProvider).valueOrNull,
      cost: ref.watch(analysisCostProvider));
});

/// Crédits que coûtera l'analyse de ce match (0 : forfait payant, équipe ou analyse offerte).
final analysisChargeProvider =
    Provider.autoDispose.family<int, int>((ref, matchId) {
  final perms =
      ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
  if (perms.contains('ai.configure')) return 0;
  if (ref.watch(featuredMatchProvider).valueOrNull == matchId) return 0;
  if (!paysCreditsAsFree(ref.watch(myCreditsProvider).valueOrNull)) return 0;
  return ref.watch(analysisCostProvider);
});

/// « Analyser » ou « Analyser · 1 crédit ».
String analyzeLabel(int cost) =>
    cost > 0 ? 'Analyser · ${creditsLabel(cost)}' : 'Analyser';

/// Matchs d'un jour qui ont déjà une analyse (une seule requête par jour affiché).
final analyzedOfDayProvider =
    FutureProvider.autoDispose.family<Set<int>, DateTime>((ref, day) async {
  final matches = await ref.watch(matchesOfDayProvider(day).future);
  final ids = [for (final m in matches) m.id];
  if (ids.isEmpty) return const <int>{};
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('match_analyses')
      .select('match_id')
      .inFilter('match_id', ids);
  return {for (final r in rows) (r['match_id'] as num).toInt()};
});

/// Ce match a-t-il déjà une analyse (enregistrée, ou obtenue pendant la session) ?
final matchAnalyzedProvider =
    Provider.autoDispose.family<bool, MatchSummary>((ref, match) {
  if (ref.watch(freshAnalysisProvider(match.id)) != null) return true;
  return ref
          .watch(analyzedOfDayProvider(dateOnly(match.kickoffAt)))
          .valueOrNull
          ?.contains(match.id) ??
      false;
});

/// Match dont l'analyse doit démarrer à l'ouverture de sa fiche (bouton des listes).
final autoAnalyzeProvider = StateProvider<int?>((ref) => null);

/// Explication quand l'analyse est réservée, avec un accès aux forfaits.
Future<void> showAnalysisLocked(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Analyse réservée', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              Consumer(
                builder: (_, ref, __) => Text(
                    'Une analyse s’obtient avec un forfait payant, ou avec '
                    '${creditsLabel(ref.watch(analysisCostProvider))} IA au forfait FREE : '
                    'un pack de crédits suffit, sans abonnement. Une fois obtenue, l’analyse reste '
                    'consultable par vous seul ; l’analyse offerte du jour reste gratuite pour tous.'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(c);
                  context.push(AppRoutes.billing);
                },
                child: const Text('Voir les forfaits et les crédits'),
              ),
            ],
          ),
        ),
      ),
    );

/// Bouton « Analyser » des listes de matchs : ouvre la fiche et lance l'analyse.
/// Rouge avec cadenas sans droit d'analyse, vert plein si l'analyse est possible
/// (avec son coût en crédits au forfait FREE), orange plein « Voir l'analyse » si
/// l'analyse est déjà obtenue.
class AnalyzeMatchButton extends ConsumerWidget {
  const AnalyzeMatchButton(
      {super.key, required this.match, this.compact = false});

  final MatchSummary match;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Déjà analysé : consultation libre, quel que soit le forfait.
    if (ref.watch(matchAnalyzedProvider(match))) {
      void open() => context.push(AppRoutes.matchDetailFor(match.id));
      if (compact) {
        return IconButton.filled(
          tooltip: 'Voir l’analyse',
          visualDensity: VisualDensity.compact,
          style: solidIconButtonStyle(context, SolidTone.orange),
          onPressed: open,
          icon: const Icon(Icons.visibility_outlined, size: 18),
        );
      }
      return FilledButton.icon(
        style: solidButtonStyle(context, SolidTone.orange, compact: true),
        onPressed: open,
        icon: const Icon(Icons.visibility_outlined, size: 16),
        label: const Text('Voir l’analyse'),
      );
    }
    if (match.status != MatchStatus.scheduled) return const SizedBox.shrink();
    final allowed = ref.watch(analysisAllowedProvider(match.id));
    final cost = ref.watch(analysisChargeProvider(match.id));
    void go() {
      if (!allowed) {
        showAnalysisLocked(context);
        return;
      }
      ref.read(autoAnalyzeProvider.notifier).state = match.id;
      context.push(AppRoutes.matchDetailFor(match.id));
    }

    final tone = allowed ? SolidTone.green : SolidTone.red;
    final icon = allowed ? Icons.auto_awesome : Icons.lock_outline;
    if (compact) {
      final button = IconButton.filled(
        tooltip: allowed
            ? (cost > 0 ? 'Analyser (${creditsLabel(cost)})' : 'Analyser')
            : 'Analyse réservée : forfait payant ou crédits',
        visualDensity: VisualDensity.compact,
        style: solidIconButtonStyle(context, tone),
        onPressed: go,
        icon: Icon(icon, size: 18),
      );
      return allowed && cost > 0
          ? Badge(label: Text('$cost'), child: button)
          : button;
    }
    return Semantics(
      button: true,
      enabled: allowed,
      child: FilledButton.icon(
        style: solidButtonStyle(context, tone, compact: true),
        onPressed: go,
        icon: Icon(icon, size: 16),
        label: Text(allowed ? analyzeLabel(cost) : 'Analyser'),
      ),
    );
  }
}
