import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../assistant/data/assistant_models.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/data/sports_models.dart';
import '../../matches/data/sports_repository.dart';
import '../../system/system_providers.dart';
import '../data/analysis_repository.dart';

/// Forfait payant, crédits disponibles ou compte de l'équipe : même règle que le serveur.
bool canAnalyzeWith(Credits? c) =>
    c != null && (c.unlimited || c.plan != 'FREE' || c.total > 0);

/// Ce compte peut-il lancer l'analyse de ce match ? L'analyse offerte du jour reste ouverte.
final analysisAllowedProvider =
    Provider.autoDispose.family<bool, int>((ref, matchId) {
  final perms =
      ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
  if (perms.contains('ai.configure')) return true;
  if (ref.watch(featuredMatchProvider).valueOrNull == matchId) return true;
  return canAnalyzeWith(ref.watch(myCreditsProvider).valueOrNull);
});

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
              const Text(
                  'Lancer une analyse demande un forfait payant ou des crédits IA. '
                  'L’analyse offerte du jour reste gratuite pour tous, et les analyses déjà '
                  'réalisées restent consultables.'),
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
/// Grisé avec un cadenas si le compte n'a ni forfait payant ni crédits.
class AnalyzeMatchButton extends ConsumerWidget {
  const AnalyzeMatchButton(
      {super.key, required this.match, this.compact = false});

  final MatchSummary match;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Déjà analysé : consultation libre, quel que soit le forfait.
    if (ref.watch(matchAnalyzedProvider(match))) {
      void open() => context.push(AppRoutes.matchDetailFor(match.id));
      if (compact) {
        return IconButton(
          tooltip: 'Voir l’analyse',
          visualDensity: VisualDensity.compact,
          onPressed: open,
          icon:
              Icon(Icons.visibility_outlined, size: 20, color: scheme.primary),
        );
      }
      return FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: open,
        icon: const Icon(Icons.visibility_outlined, size: 16),
        label: const Text('Voir l’analyse'),
      );
    }
    if (match.status != MatchStatus.scheduled) return const SizedBox.shrink();
    final allowed = ref.watch(analysisAllowedProvider(match.id));
    void go() {
      if (!allowed) {
        showAnalysisLocked(context);
        return;
      }
      ref.read(autoAnalyzeProvider.notifier).state = match.id;
      context.push(AppRoutes.matchDetailFor(match.id));
    }

    final icon = allowed ? Icons.auto_awesome : Icons.lock_outline;
    if (compact) {
      return IconButton(
        tooltip: allowed ? 'Analyser' : 'Analyse réservée aux abonnés',
        visualDensity: VisualDensity.compact,
        onPressed: go,
        icon: Icon(icon,
            size: 20,
            color: allowed ? scheme.primary : scheme.onSurfaceVariant),
      );
    }
    return Semantics(
      button: true,
      enabled: allowed,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: allowed ? scheme.primary : scheme.onSurfaceVariant,
          side: BorderSide(
              color: allowed ? scheme.primary : scheme.outlineVariant),
        ),
        onPressed: go,
        icon: Icon(icon, size: 16),
        label: const Text('Analyser'),
      ),
    );
  }
}
