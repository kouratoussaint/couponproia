// Direct en temps réel : l'app relit toutes les 30 secondes l'état des matchs proches (minute,
// score, statut) et l'applique partout où un match est affiché, sans tirer pour actualiser.
// Requête légère : seulement les matchs modifiés depuis la lecture précédente, dans une fenêtre
// de 4 heures avant à 15 minutes après maintenant. Pause quand l'app est en arrière-plan.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'sports_models.dart';
import 'sports_repository.dart';

/// État en direct d'un match (colonnes qui changent pendant la rencontre).
class LivePatch {
  const LivePatch({
    required this.matchId,
    required this.kickoffAt,
    required this.status,
    required this.sourceUpdatedAt,
    this.statusShort,
    this.elapsed,
    this.homeGoals,
    this.awayGoals,
    this.htHomeGoals,
    this.htAwayGoals,
  });

  factory LivePatch.fromJson(Map<String, dynamic> j) => LivePatch(
        matchId: (j['id'] as num).toInt(),
        kickoffAt: DateTime.parse(j['kickoff_at'] as String).toLocal(),
        status: MatchStatus.parse(j['status'] as String?),
        statusShort: j['status_short'] as String?,
        elapsed: (j['elapsed'] as num?)?.toInt(),
        homeGoals: (j['home_goals'] as num?)?.toInt(),
        awayGoals: (j['away_goals'] as num?)?.toInt(),
        htHomeGoals: (j['ht_home_goals'] as num?)?.toInt(),
        htAwayGoals: (j['ht_away_goals'] as num?)?.toInt(),
        sourceUpdatedAt:
            DateTime.parse(j['source_updated_at'] as String).toLocal(),
      );

  static const columns =
      'id, kickoff_at, status, status_short, elapsed, home_goals, away_goals, '
      'ht_home_goals, ht_away_goals, source_updated_at';

  final int matchId;
  final DateTime kickoffAt;
  final MatchStatus status;
  final String? statusShort;
  final int? elapsed;
  final int? homeGoals;
  final int? awayGoals;
  final int? htHomeGoals;
  final int? htAwayGoals;
  final DateTime sourceUpdatedAt;

  bool get isLive =>
      status == MatchStatus.live || status == MatchStatus.interrupted;

  /// Score ou statut différent (un but, une mi-temps, une fin de match) : pas seulement la minute.
  bool changesOutcome(LivePatch? before) =>
      before == null ||
      before.status != status ||
      before.statusShort != statusShort ||
      before.homeGoals != homeGoals ||
      before.awayGoals != awayGoals;
}

/// Le match avec son état en direct le plus récent (inchangé si l'état connu est plus ancien).
MatchSummary withLive(MatchSummary m, LivePatch? p) {
  if (p == null || !p.sourceUpdatedAt.isAfter(m.sourceUpdatedAt)) return m;
  return MatchSummary(
    id: m.id,
    season: m.season,
    kickoffAt: m.kickoffAt,
    status: p.status,
    competition: m.competition,
    home: m.home,
    away: m.away,
    sourceUpdatedAt: p.sourceUpdatedAt,
    statusShort: p.statusShort,
    elapsed: p.elapsed,
    homeGoals: p.homeGoals,
    awayGoals: p.awayGoals,
    htHomeGoals: p.htHomeGoals,
    htAwayGoals: p.htAwayGoals,
    round: m.round,
    venue: m.venue,
    referee: m.referee,
  );
}

/// Intervalle de lecture : 30 s s'il y a un match en cours ou qui commence dans les 15 minutes,
/// sinon 2 minutes (pour voir les coups d'envoi).
Duration pollInterval(Iterable<LivePatch> known, DateTime now) {
  final active = known.any((p) =>
      p.isLive ||
      (p.status == MatchStatus.scheduled &&
          p.kickoffAt.difference(now).inMinutes <= 15));
  return active ? const Duration(seconds: 30) : const Duration(minutes: 2);
}

class LiveUpdates extends StateNotifier<Map<int, LivePatch>> {
  LiveUpdates(this._client) : super(const {});

  /// null : pas de serveur configuré (tests, configuration absente) → aucune lecture.
  final SupabaseClient? _client;

  Timer? _timer;
  DateTime? _cursor;
  bool _running = false;
  bool _paused = true;

  void start() {
    if (!_paused) return;
    _paused = false;
    unawaited(poll());
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
  }

  void _schedule() {
    _timer?.cancel();
    if (_paused || !mounted) return;
    _timer = Timer(pollInterval(state.values, DateTime.now()), poll);
  }

  /// Relit l'état des matchs proches ; à la première lecture, toute la fenêtre.
  Future<void> poll() async {
    final client = _client;
    if (_running || !mounted || client == null) return;
    _running = true;
    try {
      final now = DateTime.now().toUtc();
      var q = client
          .from('matches')
          .select(LivePatch.columns)
          .gte('kickoff_at',
              now.subtract(const Duration(hours: 4)).toIso8601String())
          .lte('kickoff_at',
              now.add(const Duration(minutes: 15)).toIso8601String());
      if (_cursor != null) {
        q = q.gt('source_updated_at', _cursor!.toUtc().toIso8601String());
      }
      final rows = await q.order('source_updated_at').limit(300);
      if (!mounted) return;
      if (rows.isNotEmpty) {
        final next = {...state};
        for (final r in rows) {
          final p = LivePatch.fromJson(r);
          next[p.matchId] = p;
          if (_cursor == null || p.sourceUpdatedAt.isAfter(_cursor!)) {
            _cursor = p.sourceUpdatedAt;
          }
        }
        // Les matchs sortis de la fenêtre ne sont plus suivis.
        final oldest = DateTime.now().subtract(const Duration(hours: 5));
        next.removeWhere((_, p) => p.kickoffAt.isBefore(oldest));
        state = next;
      } else {
        _cursor ??= now;
      }
    } catch (_) {
      // Hors ligne ou erreur passagère : nouvel essai au prochain passage.
    } finally {
      _running = false;
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final liveUpdatesProvider =
    StateNotifierProvider<LiveUpdates, Map<int, LivePatch>>((ref) {
  SupabaseClient? client;
  try {
    client = ref.watch(supabaseClientProvider);
  } catch (_) {
    client = null;
  }
  return LiveUpdates(client);
});

/// Matchs dont le score ou le statut a changé entre deux états (pas seulement la minute).
/// Vide au premier chargement.
Set<int> outcomeChanges(
    Map<int, LivePatch>? before, Map<int, LivePatch> after) {
  if (before == null || before.isEmpty) return const {};
  return {
    for (final e in after.entries)
      if (e.value.changesOutcome(before[e.key])) e.key
  };
}

/// Matchs d'un jour avec leur état en direct.
final liveMatchesOfDayProvider =
    Provider.family<AsyncValue<List<MatchSummary>>, DateTime>((ref, day) {
  final live = ref.watch(liveUpdatesProvider);
  return ref
      .watch(matchesOfDayProvider(day))
      .whenData((list) => [for (final m in list) withLive(m, live[m.id])]);
});

/// Un match avec son état en direct.
final liveMatchProvider =
    Provider.family<AsyncValue<MatchSummary?>, int>((ref, id) {
  final p = ref.watch(liveUpdatesProvider.select((s) => s[id]));
  return ref
      .watch(matchProvider(id))
      .whenData((m) => m == null ? null : withLive(m, p));
});
