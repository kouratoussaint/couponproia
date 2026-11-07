/// Modèles des données football lues dans Supabase (écrites par la synchronisation).
library;

int _int(Object? v) => (v as num).toInt();
int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();
double _double(Object? v) => (v as num).toDouble();
double? _doubleOrNull(Object? v) => v == null ? null : (v as num).toDouble();
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();

class TeamRef {
  const TeamRef({required this.id, required this.name, this.logoUrl});

  factory TeamRef.fromJson(Map<String, dynamic> json) => TeamRef(
        id: _int(json['id']),
        name: json['name'] as String,
        logoUrl: json['logo_url'] as String?,
      );

  final int id;
  final String name;
  final String? logoUrl;
}

class CompetitionRef {
  const CompetitionRef({
    required this.id,
    required this.name,
    this.country,
    this.logoUrl,
    this.currentSeason,
    this.priority = 100,
  });

  /// Nom affiché : « Ligue 1 (Burkina-Faso) » quand deux compétitions suivies portent le même nom.
  factory CompetitionRef.fromJson(Map<String, dynamic> json) => CompetitionRef(
        id: _int(json['id']),
        name: json['display_name'] as String? ?? json['name'] as String,
        country: json['country'] as String?,
        logoUrl: json['logo_url'] as String?,
        currentSeason: _intOrNull(json['current_season']),
        priority: _intOrNull(json['priority']) ?? 100,
      );

  final int id;
  final String name;
  final String? country;
  final String? logoUrl;
  final int? currentSeason;

  /// Plus petit = plus important (ordre des listes et de l'accueil).
  final int priority;
}

enum MatchStatus {
  scheduled,
  live,
  finished,
  postponed,
  cancelled,
  abandoned,
  interrupted,
  awarded,
  unknown;

  static MatchStatus parse(String? value) => MatchStatus.values
      .firstWhere((s) => s.name == value, orElse: () => MatchStatus.unknown);
}

class MatchSummary {
  const MatchSummary({
    required this.id,
    required this.season,
    required this.kickoffAt,
    required this.status,
    required this.competition,
    required this.home,
    required this.away,
    required this.sourceUpdatedAt,
    this.statusShort,
    this.elapsed,
    this.homeGoals,
    this.awayGoals,
    this.htHomeGoals,
    this.htAwayGoals,
    this.round,
    this.venue,
    this.referee,
  });

  factory MatchSummary.fromJson(Map<String, dynamic> json) => MatchSummary(
        id: _int(json['id']),
        season: _int(json['season']),
        kickoffAt: _date(json['kickoff_at']),
        status: MatchStatus.parse(json['status'] as String?),
        statusShort: json['status_short'] as String?,
        elapsed: _intOrNull(json['elapsed']),
        homeGoals: _intOrNull(json['home_goals']),
        awayGoals: _intOrNull(json['away_goals']),
        htHomeGoals: _intOrNull(json['ht_home_goals']),
        htAwayGoals: _intOrNull(json['ht_away_goals']),
        round: json['round'] as String?,
        venue: json['venue'] as String?,
        referee: json['referee'] as String?,
        sourceUpdatedAt: _date(json['source_updated_at']),
        competition: CompetitionRef.fromJson(
            json['competition'] as Map<String, dynamic>),
        home: TeamRef.fromJson(json['home'] as Map<String, dynamic>),
        away: TeamRef.fromJson(json['away'] as Map<String, dynamic>),
      );

  final int id;
  final int season;
  final DateTime kickoffAt;
  final MatchStatus status;
  final String? statusShort;
  final int? elapsed;
  final int? homeGoals;
  final int? awayGoals;
  final int? htHomeGoals;
  final int? htAwayGoals;
  final String? round;
  final String? venue;
  final String? referee;
  final DateTime sourceUpdatedAt;
  final CompetitionRef competition;
  final TeamRef home;
  final TeamRef away;

  bool get isLive =>
      status == MatchStatus.live || status == MatchStatus.interrupted;
  bool get hasScore => homeGoals != null && awayGoals != null;
}

class OddsLine {
  const OddsLine({
    required this.marketCode,
    required this.outcomeCode,
    required this.median,
    required this.best,
    required this.bookmakers,
    required this.capturedAt,
    this.line,
  });

  factory OddsLine.fromJson(Map<String, dynamic> json) => OddsLine(
        marketCode: json['market_code'] as String,
        outcomeCode: json['outcome_code'] as String,
        line: _doubleOrNull(json['line']),
        median: _double(json['odd_median']),
        best: _double(json['odd_best']),
        bookmakers: _int(json['bookmakers_count']),
        capturedAt: _date(json['captured_at']),
      );

  final String marketCode;
  final String outcomeCode;
  final double? line;
  final double median;
  final double best;
  final int bookmakers;
  final DateTime capturedAt;
}

class StandingRow {
  const StandingRow({
    required this.group,
    required this.rank,
    required this.team,
    required this.points,
    required this.played,
    required this.win,
    required this.draw,
    required this.lose,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDiff,
    this.form,
    this.description,
  });

  factory StandingRow.fromJson(Map<String, dynamic> json) => StandingRow(
        group: (json['group_name'] as String?) ?? '',
        rank: _int(json['rank']),
        team: TeamRef.fromJson(json['team'] as Map<String, dynamic>),
        points: _int(json['points']),
        played: _int(json['played']),
        win: _int(json['win']),
        draw: _int(json['draw']),
        lose: _int(json['lose']),
        goalsFor: _int(json['goals_for']),
        goalsAgainst: _int(json['goals_against']),
        goalDiff: _int(json['goal_diff']),
        form: json['form'] as String?,
        description: json['description'] as String?,
      );

  final String group;
  final int rank;
  final TeamRef team;
  final int points;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDiff;
  final String? form;
  final String? description;
}

class SyncRun {
  const SyncRun({
    required this.id,
    required this.job,
    required this.status,
    required this.startedAt,
    required this.requestsUsed,
    required this.itemsUpserted,
    this.finishedAt,
    this.requestsRemaining,
    this.error,
  });

  factory SyncRun.fromJson(Map<String, dynamic> json) => SyncRun(
        id: _int(json['id']),
        job: json['job'] as String,
        status: json['status'] as String,
        startedAt: _date(json['started_at']),
        finishedAt:
            json['finished_at'] == null ? null : _date(json['finished_at']),
        requestsUsed: _int(json['requests_used']),
        requestsRemaining: _intOrNull(json['requests_remaining']),
        itemsUpserted: _int(json['items_upserted']),
        error: json['error'] as String?,
      );

  final int id;
  final String job;
  final String status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int requestsUsed;
  final int? requestsRemaining;
  final int itemsUpserted;
  final String? error;
}
