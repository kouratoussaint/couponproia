import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'sports_format.dart';
import 'sports_models.dart';

const _matchColumns = 'id, season, round, kickoff_at, status, status_short, elapsed, '
    'home_goals, away_goals, ht_home_goals, ht_away_goals, venue, referee, source_updated_at, '
    'competition:competitions(id, name, country, logo_url, current_season), '
    'home:teams!matches_home_team_fk(id, name, logo_url), '
    'away:teams!matches_away_team_fk(id, name, logo_url)';

/// Lecture des données football. Tout est en lecture seule côté app :
/// seules les synchronisations serveur écrivent ces tables.
class SportsRepository {
  SportsRepository(this._client);

  final SupabaseClient _client;

  List<MatchSummary> _matches(List<dynamic> rows) =>
      rows.map((r) => MatchSummary.fromJson(r as Map<String, dynamic>)).toList();

  Future<List<MatchSummary>> matchesOfDay(DateTime day) async {
    final (from, to) = utcRangeForLocalDay(day);
    final rows = await _client
        .from('matches')
        .select(_matchColumns)
        .gte('kickoff_at', from.toIso8601String())
        .lt('kickoff_at', to.toIso8601String())
        .order('kickoff_at')
        .limit(500);
    return _matches(rows);
  }

  Future<MatchSummary?> match(int id) async {
    final row = await _client.from('matches').select(_matchColumns).eq('id', id).maybeSingle();
    return row == null ? null : MatchSummary.fromJson(row);
  }

  Future<List<OddsLine>> latestOdds(int matchId) async {
    final rows = await _client
        .from('latest_odds')
        .select('market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at')
        .eq('match_id', matchId);
    return rows.map(OddsLine.fromJson).toList();
  }

  /// Derniers matchs terminés d'une équipe, avant une date.
  Future<List<MatchSummary>> recentMatches(int teamId, DateTime before, {int limit = 5}) async {
    final rows = await _client
        .from('matches')
        .select(_matchColumns)
        .or('home_team_id.eq.$teamId,away_team_id.eq.$teamId')
        .eq('status', 'finished')
        .lt('kickoff_at', before.toUtc().toIso8601String())
        .order('kickoff_at', ascending: false)
        .limit(limit);
    return _matches(rows);
  }

  /// Confrontations directes présentes dans les données synchronisées.
  Future<List<MatchSummary>> headToHead(int teamA, int teamB, DateTime before, {int limit = 5}) async {
    final rows = await _client
        .from('matches')
        .select(_matchColumns)
        .or('and(home_team_id.eq.$teamA,away_team_id.eq.$teamB),and(home_team_id.eq.$teamB,away_team_id.eq.$teamA)')
        .eq('status', 'finished')
        .lt('kickoff_at', before.toUtc().toIso8601String())
        .order('kickoff_at', ascending: false)
        .limit(limit);
    return _matches(rows);
  }

  Future<List<CompetitionRef>> competitions() async {
    final rows = await _client
        .from('competitions')
        .select('id, name, country, logo_url, current_season')
        .eq('is_active', true)
        .order('priority');
    return rows.map(CompetitionRef.fromJson).toList();
  }

  Future<CompetitionRef?> competition(int id) async {
    final row = await _client
        .from('competitions')
        .select('id, name, country, logo_url, current_season')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : CompetitionRef.fromJson(row);
  }

  Future<List<StandingRow>> standings(int competitionId, int season) async {
    final rows = await _client
        .from('standings')
        .select('group_name, rank, points, played, win, draw, lose, goals_for, goals_against, '
            'goal_diff, form, description, team:teams(id, name, logo_url)')
        .eq('competition_id', competitionId)
        .eq('season', season)
        .order('group_name')
        .order('rank');
    return rows.map(StandingRow.fromJson).toList();
  }

  Future<List<SyncRun>> syncRuns({int limit = 20}) async {
    final rows = await _client
        .from('sync_runs')
        .select('id, job, status, started_at, finished_at, requests_used, requests_remaining, items_upserted, error')
        .order('started_at', ascending: false)
        .limit(limit);
    return rows.map(SyncRun.fromJson).toList();
  }

  Future<int?> dailyBudget() async {
    final row = await _client
        .from('app_settings')
        .select('value')
        .eq('key', 'sports.daily_request_budget')
        .maybeSingle();
    final value = row?['value'];
    return value is num ? value.toInt() : null;
  }

  Future<void> triggerSync(String job) async {
    await _client.functions.invoke('sports-sync', body: {'job': job});
  }
}

final sportsRepositoryProvider = Provider<SportsRepository>(
  (ref) => SportsRepository(ref.watch(supabaseClientProvider)),
);

final matchesOfDayProvider = FutureProvider.family<List<MatchSummary>, DateTime>(
  (ref, day) => ref.watch(sportsRepositoryProvider).matchesOfDay(day),
);

final matchProvider = FutureProvider.family<MatchSummary?, int>(
  (ref, id) => ref.watch(sportsRepositoryProvider).match(id),
);

final latestOddsProvider = FutureProvider.family<List<OddsLine>, int>(
  (ref, matchId) => ref.watch(sportsRepositoryProvider).latestOdds(matchId),
);

final recentMatchesProvider = FutureProvider.family<List<MatchSummary>, (int, DateTime)>(
  (ref, key) => ref.watch(sportsRepositoryProvider).recentMatches(key.$1, key.$2),
);

final headToHeadProvider = FutureProvider.family<List<MatchSummary>, (int, int, DateTime)>(
  (ref, key) => ref.watch(sportsRepositoryProvider).headToHead(key.$1, key.$2, key.$3),
);

final competitionsProvider = FutureProvider<List<CompetitionRef>>(
  (ref) => ref.watch(sportsRepositoryProvider).competitions(),
);

final competitionProvider = FutureProvider.family<CompetitionRef?, int>(
  (ref, id) => ref.watch(sportsRepositoryProvider).competition(id),
);

final standingsProvider = FutureProvider.family<List<StandingRow>, (int, int)>(
  (ref, key) => ref.watch(sportsRepositoryProvider).standings(key.$1, key.$2),
);

final syncRunsProvider = FutureProvider.autoDispose<List<SyncRun>>(
  (ref) => ref.watch(sportsRepositoryProvider).syncRuns(),
);

final dailyBudgetProvider = FutureProvider.autoDispose<int?>(
  (ref) => ref.watch(sportsRepositoryProvider).dailyBudget(),
);
