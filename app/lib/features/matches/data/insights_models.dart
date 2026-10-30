// Données de l'onglet Stats d'un match (fonction match_insights) et probabilités 1/N/2 du marché.
// Tout vient des résultats enregistrés et des cotes relevées : rien n'est estimé ici.

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
List<Map<String, dynamic>> _list(Object? v) => [
      for (final e in (v as List? ?? const [])) _map(e),
    ];

/// Probabilités 1/N/2 selon les cotes (cote médiane, marge des bookmakers retirée).
class Market1x2 {
  const Market1x2({
    required this.matchId,
    required this.pHome,
    required this.pDraw,
    required this.pAway,
    required this.bookmakers,
    this.capturedAt,
  });

  factory Market1x2.fromJson(Map<String, dynamic> j) => Market1x2(
        matchId: _i(j['match_id']),
        pHome: _d(j['p_home']),
        pDraw: _d(j['p_draw']),
        pAway: _d(j['p_away']),
        bookmakers: _i(j['bookmakers']),
        capturedAt: _date(j['captured_at']),
      );

  final int matchId;
  final double pHome;
  final double pDraw;
  final double pAway;
  final int bookmakers;
  final DateTime? capturedAt;
}

class StandingLine {
  const StandingLine({
    required this.rank,
    required this.teamId,
    required this.name,
    required this.played,
    required this.goalDiff,
    required this.points,
    this.logoUrl,
    this.form,
    this.description,
  });

  factory StandingLine.fromJson(Map<String, dynamic> j) => StandingLine(
        rank: _i(j['rank']),
        teamId: _i(j['team_id']),
        name: j['name'] as String? ?? '?',
        logoUrl: j['logo_url'] as String?,
        played: _i(j['played']),
        goalDiff: _i(j['goal_diff']),
        points: _i(j['points']),
        form: j['form'] as String?,
        description: j['description'] as String?,
      );

  final int rank;
  final int teamId;
  final String name;
  final String? logoUrl;
  final int played;
  final int goalDiff;
  final int points;
  final String? form;
  final String? description;

  /// Zone du classement d'après la description du fournisseur.
  StandingZone get zone => standingZone(description);
}

enum StandingZone { none, top, qualification, relegation }

StandingZone standingZone(String? description) {
  final d = (description ?? '').toLowerCase();
  if (d.isEmpty) return StandingZone.none;
  if (d.contains('relegation') || d.contains('relégation')) {
    return StandingZone.relegation;
  }
  if (d.contains('champions league') ||
      d.contains('promotion') ||
      d.contains('final series') ||
      d.contains('title')) {
    return d.contains('qualif') || d.contains('play')
        ? StandingZone.qualification
        : StandingZone.top;
  }
  return StandingZone.qualification;
}

/// Libellé français de la zone (description du fournisseur traduite pour les cas courants).
String zoneLabel(String? description) {
  final d = (description ?? '').toLowerCase();
  if (d.isEmpty) return '';
  if (d.contains('relegation')) {
    return d.contains('play') ? 'Barrage de relégation' : 'Zone de relégation';
  }
  if (d.contains('champions league')) {
    return d.contains('qualif')
        ? 'Qualification Ligue des champions'
        : 'Place en Ligue des champions';
  }
  if (d.contains('europa league')) return 'Place en Ligue Europa';
  if (d.contains('conference league')) return 'Place en Ligue Conférence';
  if (d.contains('promotion')) return 'Zone de promotion';
  if (d.contains('play')) return 'Barrages';
  return description!;
}

class FormEntry {
  const FormEntry({
    required this.kickoffAt,
    required this.opponent,
    required this.atHome,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.result,
    required this.competition,
  });

  factory FormEntry.fromJson(Map<String, dynamic> j) => FormEntry(
        kickoffAt: _date(j['kickoff_at']) ?? DateTime(2000),
        opponent: j['opponent'] as String? ?? '?',
        atHome: j['at_home'] == true,
        goalsFor: _i(j['gf']),
        goalsAgainst: _i(j['ga']),
        result: j['result'] as String? ?? 'D',
        competition: j['competition'] as String? ?? '',
      );

  final DateTime kickoffAt;
  final String opponent;
  final bool atHome;
  final int goalsFor;
  final int goalsAgainst;

  /// W, D ou L (pour l'équipe concernée).
  final String result;
  final String competition;

  /// V / N / D en français.
  String get letter => switch (result) { 'W' => 'V', 'L' => 'D', _ => 'N' };
  int get points => switch (result) { 'W' => 3, 'D' => 1, _ => 0 };
}

int formPoints(List<FormEntry> form) =>
    form.fold(0, (sum, e) => sum + e.points);

class SeasonStats {
  const SeasonStats({
    required this.played,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.cleanSheets,
    required this.threePlus,
    required this.btts,
  });

  factory SeasonStats.fromJson(Map<String, dynamic> j) => SeasonStats(
        played: _i(j['played']),
        goalsFor: _i(j['goals_for']),
        goalsAgainst: _i(j['goals_against']),
        cleanSheets: _i(j['clean_sheets']),
        threePlus: _i(j['three_plus']),
        btts: _i(j['btts']),
      );

  final int played;
  final int goalsFor;
  final int goalsAgainst;
  final int cleanSheets;
  final int threePlus;
  final int btts;

  double get goalsForAvg => played == 0 ? 0 : goalsFor / played;
  double get goalsAgainstAvg => played == 0 ? 0 : goalsAgainst / played;
}

class Streak {
  const Streak({
    required this.key,
    required this.length,
    required this.atLeast,
    this.from,
    this.to,
  });

  factory Streak.fromJson(Map<String, dynamic> j) => Streak(
        key: j['key'] as String,
        length: _i(j['length']),
        atLeast: j['at_least'] == true,
        from: _date(j['from']),
        to: _date(j['to']),
      );

  final String key;
  final int length;

  /// La série couvre tous les matchs enregistrés : elle peut être plus longue.
  final bool atLeast;
  final DateTime? from;
  final DateTime? to;

  String get label {
    final cap = atLeast ? 'Au moins $length' : '$length';
    return switch (key) {
      'scored' =>
        'A marqué lors ${atLeast ? 'd’au moins' : 'de'} $length matchs de suite',
      'unbeaten' => '$cap matchs sans défaite',
      'wins' => '$cap victoires de suite',
      'losses' => '$cap défaites de suite',
      'winless' => '$cap matchs sans victoire',
      'clean_sheets' => '$cap matchs sans encaisser de but',
      'conceded' =>
        'A encaissé lors ${atLeast ? 'd’au moins' : 'de'} $length matchs de suite',
      _ => '$cap matchs',
    };
  }
}

/// Séries utiles à afficher : on évite les doublons (3 victoires = aussi 3 matchs sans défaite).
List<Streak> usefulStreaks(List<Streak> all) {
  int len(String k) =>
      all.where((s) => s.key == k).map((s) => s.length).firstOrNull ?? 0;
  return [
    for (final s in all)
      if (!(s.key == 'unbeaten' && len('wins') >= s.length) &&
          !(s.key == 'winless' && len('losses') >= s.length) &&
          !(s.key == 'conceded' && len('losses') >= s.length))
        s
  ]..sort((a, b) => b.length.compareTo(a.length));
}

class H2hMatch {
  const H2hMatch({
    required this.kickoffAt,
    required this.home,
    required this.away,
    required this.homeGoals,
    required this.awayGoals,
    required this.competition,
    required this.homeIsMatchHome,
  });

  factory H2hMatch.fromJson(Map<String, dynamic> j) => H2hMatch(
        kickoffAt: _date(j['kickoff_at']) ?? DateTime(2000),
        home: j['home'] as String? ?? '?',
        away: j['away'] as String? ?? '?',
        homeGoals: _i(j['home_goals']),
        awayGoals: _i(j['away_goals']),
        competition: j['competition'] as String? ?? '',
        homeIsMatchHome: j['home_is_match_home'] == true,
      );

  final DateTime kickoffAt;
  final String home;
  final String away;
  final int homeGoals;
  final int awayGoals;
  final String competition;
  final bool homeIsMatchHome;

  /// Résultat du point de vue de l'équipe qui reçoit dans le match analysé : V / N / D.
  String get letterForMatchHome {
    if (homeGoals == awayGoals) return 'N';
    final homeWon = homeGoals > awayGoals;
    return homeWon == homeIsMatchHome ? 'V' : 'D';
  }
}

class HeadToHead {
  const HeadToHead({
    required this.count,
    required this.homeWins,
    required this.draws,
    required this.awayWins,
    required this.matches,
    this.avgGoals,
    this.first,
    this.last,
  });

  factory HeadToHead.fromJson(Map<String, dynamic> j) => HeadToHead(
        count: _i(j['count']),
        homeWins: _i(j['home_wins']),
        draws: _i(j['draws']),
        awayWins: _i(j['away_wins']),
        avgGoals: j['avg_goals'] == null ? null : _d(j['avg_goals']),
        first: _date(j['first']),
        last: _date(j['last']),
        matches: [for (final m in _list(j['matches'])) H2hMatch.fromJson(m)],
      );

  final int count;
  final int homeWins;
  final int draws;
  final int awayWins;
  final double? avgGoals;
  final DateTime? first;
  final DateTime? last;
  final List<H2hMatch> matches;
}

class MatchInsights {
  const MatchInsights({
    required this.computedAt,
    required this.standings,
    required this.homeForm,
    required this.awayForm,
    required this.homeAtHome,
    required this.awayAway,
    required this.homeSeason,
    required this.awaySeason,
    required this.homeStreaks,
    required this.awayStreaks,
    required this.homeAtHomeStreaks,
    required this.awayAwayStreaks,
    required this.h2h,
    this.standingsUpdatedAt,
  });

  factory MatchInsights.fromJson(Map<String, dynamic> j) {
    final st = _map(j['standings']);
    final form = _map(j['form']);
    final season = _map(j['season']);
    final streaks = _map(j['streaks']);
    List<FormEntry> f(String k) =>
        [for (final e in _list(form[k])) FormEntry.fromJson(e)];
    List<Streak> s(String k) =>
        [for (final e in _list(streaks[k])) Streak.fromJson(e)];
    return MatchInsights(
      computedAt: _date(j['computed_at']) ?? DateTime.now(),
      standingsUpdatedAt: _date(st['updated_at']),
      standings: [for (final r in _list(st['rows'])) StandingLine.fromJson(r)],
      homeForm: f('home'),
      awayForm: f('away'),
      homeAtHome: f('home_at_home'),
      awayAway: f('away_away'),
      homeSeason: SeasonStats.fromJson(_map(season['home'])),
      awaySeason: SeasonStats.fromJson(_map(season['away'])),
      homeStreaks: s('home'),
      awayStreaks: s('away'),
      homeAtHomeStreaks: s('home_at_home'),
      awayAwayStreaks: s('away_away'),
      h2h: HeadToHead.fromJson(_map(j['h2h'])),
    );
  }

  final DateTime computedAt;
  final DateTime? standingsUpdatedAt;
  final List<StandingLine> standings;
  final List<FormEntry> homeForm;
  final List<FormEntry> awayForm;
  final List<FormEntry> homeAtHome;
  final List<FormEntry> awayAway;
  final SeasonStats homeSeason;
  final SeasonStats awaySeason;
  final List<Streak> homeStreaks;
  final List<Streak> awayStreaks;
  final List<Streak> homeAtHomeStreaks;
  final List<Streak> awayAwayStreaks;
  final HeadToHead h2h;

  StandingLine? standingOf(int teamId) {
    for (final r in standings) {
      if (r.teamId == teamId) return r;
    }
    return null;
  }
}
