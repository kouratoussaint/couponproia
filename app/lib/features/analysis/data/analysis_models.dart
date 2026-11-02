/// Modèles de l'analyse d'un match : fiche du moteur statistique (toujours présente)
/// et texte de l'IA (présent seulement s'il a passé les contrôles anti-invention).
library;

double _d(Object? v) => (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
List<String> _strings(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

enum Reliability {
  faible,
  moyenne,
  bonne;

  static Reliability parse(Object? v) => Reliability.values
      .firstWhere((r) => r.name == v, orElse: () => Reliability.faible);
}

class FicheOddsLine {
  const FicheOddsLine({
    required this.key,
    required this.oddMedian,
    required this.oddBest,
    required this.bookmakers,
    this.impliedProbability,
    this.modelProbability,
    this.edge,
  });

  factory FicheOddsLine.fromJson(Map<String, dynamic> j) => FicheOddsLine(
        key: j['key'] as String,
        oddMedian: _d(j['odd_median']),
        oddBest: _d(j['odd_best']),
        bookmakers: _i(j['bookmakers']),
        impliedProbability: _dn(j['implied_probability']),
        modelProbability: _dn(j['model_probability']),
        edge: _dn(j['edge']),
      );

  final String key;
  final double oddMedian;
  final double oddBest;
  final int bookmakers;
  final double? impliedProbability;
  final double? modelProbability;
  final double? edge;
}

class TopScore {
  const TopScore(this.score, this.probability);

  final String score;
  final double probability;
}

/// Fiche calculée par le moteur (données réelles antérieures au coup d'envoi).
class AnalysisFiche {
  const AnalysisFiche({
    required this.engineVersion,
    required this.reliability,
    required this.expectedGoalsHome,
    required this.expectedGoalsAway,
    required this.probabilities,
    required this.topScores,
    required this.competitionMatches,
    required this.homeTeamHomeMatches,
    required this.awayTeamAwayMatches,
    required this.homeForm,
    required this.awayForm,
    required this.marketLines,
    required this.missing,
    this.beatsBaseline = const {},
    this.marketCapturedAt,
  });

  factory AnalysisFiche.fromJson(Map<String, dynamic> j) {
    final model = _map(j['model']);
    final sample = _map(j['sample']);
    final teams = _map(j['teams']);
    final market = _map(j['market']);
    final probs = _map(model['probabilities']);
    return AnalysisFiche(
      engineVersion: j['engine_version'] as String? ?? '?',
      reliability: Reliability.parse(j['reliability']),
      expectedGoalsHome: _d(model['expected_goals_home'] ?? 0),
      expectedGoalsAway: _d(model['expected_goals_away'] ?? 0),
      probabilities: {for (final e in probs.entries) e.key: _d(e.value)},
      topScores: [
        for (final s in (model['top_scores'] as List? ?? const []))
          TopScore((s as Map)['score'] as String, _d(s['probability'])),
      ],
      competitionMatches: _i(sample['competition_matches']),
      homeTeamHomeMatches: _i(sample['home_team_home_matches']),
      awayTeamAwayMatches: _i(sample['away_team_away_matches']),
      homeForm: _map(teams['home'])['form'] as String? ?? '',
      awayForm: _map(teams['away'])['form'] as String? ?? '',
      marketLines: [
        for (final l in (market['lines'] as List? ?? const []))
          FicheOddsLine.fromJson(_map(l)),
      ],
      missing: _strings(j['missing']),
      marketCapturedAt: market['captured_at'] is String
          ? DateTime.tryParse(market['captured_at'] as String)?.toLocal()
          : null,
      beatsBaseline: {
        for (final e
            in _map(_map(j['engine_quality'])['beats_baseline']).entries)
          e.key: e.value == true,
      },
    );
  }

  final String engineVersion;
  final Reliability reliability;
  final double expectedGoalsHome;
  final double expectedGoalsAway;
  final Map<String, double> probabilities;
  final List<TopScore> topScores;
  final int competitionMatches;
  final int homeTeamHomeMatches;
  final int awayTeamAwayMatches;
  final String homeForm;
  final String awayForm;
  final List<FicheOddsLine> marketLines;
  final List<String> missing;

  /// Heure du dernier relevé de cotes utilisé par la fiche.
  final DateTime? marketCapturedAt;

  /// Par famille de marchés (1X2, OU, BTTS) : le moteur a-t-il battu la référence sur l'historique ?
  final Map<String, bool> beatsBaseline;

  double? p(String key) => probabilities[key];

  /// Familles où le moteur ne fait pas mieux qu'une simple fréquence.
  List<String> get weakGroups => [
        for (final e in beatsBaseline.entries)
          if (!e.value) e.key
      ];

  /// Lignes de cotes comparables au modèle (probabilité implicite connue).
  List<FicheOddsLine> get comparableLines => marketLines
      .where((l) => l.impliedProbability != null && l.modelProbability != null)
      .toList();
}

class MarketPick {
  const MarketPick({
    required this.key,
    required this.modelProbability,
    required this.justification,
    this.oddMedian,
    this.impliedProbability,
    this.edge,
  });

  factory MarketPick.fromJson(Map<String, dynamic> j) => MarketPick(
        key: j['cle'] as String,
        modelProbability: _d(j['probabilite_modele']),
        justification: j['justification'] as String? ?? '',
        oddMedian: _dn(j['cote_mediane']),
        impliedProbability: _dn(j['probabilite_implicite']),
        edge: _dn(j['ecart']),
      );

  final String key;
  final double modelProbability;
  final String justification;
  final double? oddMedian;
  final double? impliedProbability;
  final double? edge;
}

/// Texte de l'IA, validé côté serveur.
class AiAnalysis {
  const AiAnalysis({
    required this.summary,
    required this.form,
    required this.homeFactors,
    required this.awayFactors,
    required this.trends,
    required this.picks,
    required this.risks,
    required this.missing,
    required this.conclusion,
    required this.recommendationPossible,
  });

  factory AiAnalysis.fromJson(Map<String, dynamic> j) => AiAnalysis(
        summary: j['resume'] as String? ?? '',
        form: j['forme'] as String? ?? '',
        homeFactors: _strings(j['facteurs_domicile']),
        awayFactors: _strings(j['facteurs_exterieur']),
        trends: _strings(j['tendances']),
        picks: [
          for (final p in (j['marches_envisageables'] as List? ?? const []))
            MarketPick.fromJson(_map(p))
        ],
        risks: _strings(j['risques']),
        missing: _strings(j['informations_manquantes']),
        conclusion: j['conclusion'] as String? ?? '',
        recommendationPossible: j['recommandation_possible'] == true,
      );

  final String summary;
  final String form;
  final List<String> homeFactors;
  final List<String> awayFactors;
  final List<String> trends;
  final List<MarketPick> picks;
  final List<String> risks;
  final List<String> missing;
  final String conclusion;
  final bool recommendationPossible;
}

class MatchAnalysis {
  const MatchAnalysis({
    required this.id,
    required this.matchId,
    required this.engineVersion,
    required this.status,
    required this.fiche,
    required this.createdAt,
    this.statusReason,
    this.provider,
    this.model,
    this.ai,
    this.cached = true,
    this.sourceUpdatedAt,
  });

  factory MatchAnalysis.fromJson(Map<String, dynamic> j) => MatchAnalysis(
        id: _i(j['id']),
        matchId: _i(j['match_id']),
        engineVersion: j['engine_version'] as String,
        status: j['status'] as String,
        statusReason: j['status_reason'] as String?,
        provider: j['provider'] as String?,
        model: j['model'] as String?,
        fiche: AnalysisFiche.fromJson(_map(j['stats'])),
        ai: j['analysis'] is Map
            ? AiAnalysis.fromJson(_map(j['analysis']))
            : null,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        sourceUpdatedAt: j['source_updated_at'] is String
            ? DateTime.tryParse(j['source_updated_at'] as String)?.toLocal()
            : null,
        cached: j['cached'] != false,
      );

  final int id;
  final int matchId;
  final String engineVersion;

  /// « ok » (fiche + texte IA validé) ou « stats_only » (fiche seule).
  final String status;
  final String? statusReason;
  final String? provider;
  final String? model;
  final AnalysisFiche fiche;
  final AiAnalysis? ai;
  final DateTime createdAt;

  /// Données les plus récentes prises en compte (dernier match joué ou relevé de cotes).
  final DateTime? sourceUpdatedAt;
  final bool cached;

  bool get hasAi => status == 'ok' && ai != null;
}

class Metrics {
  const Metrics({
    required this.matches,
    required this.brierModel,
    required this.brierBaseline,
    required this.loglossModel,
    required this.loglossBaseline,
    required this.accuracyModel,
    this.accuracyBaseline,
  });

  factory Metrics.fromJson(Map<String, dynamic> j) => Metrics(
        matches: _i(j['matches']),
        brierModel: _d(j['brierModel']),
        brierBaseline: _d(j['brierBaseline']),
        loglossModel: _d(j['loglossModel']),
        loglossBaseline: _d(j['loglossBaseline']),
        accuracyModel: _d(j['accuracyModel']),
        accuracyBaseline: _dn(j['accuracyBaseline']),
      );

  final int matches;
  final double brierModel;
  final double brierBaseline;
  final double loglossModel;
  final double loglossBaseline;
  final double accuracyModel;
  final double? accuracyBaseline;

  bool get beatsBaseline => brierModel < brierBaseline;
}

class CalibrationBin {
  const CalibrationBin(
      this.from, this.to, this.count, this.predicted, this.observed);

  final double from;
  final double to;
  final int count;
  final double predicted;
  final double observed;
}

/// Évaluation du moteur sur l'historique (marche avant, sans fuite du futur).
class EngineEvaluation {
  const EngineEvaluation({
    required this.engineVersion,
    required this.createdAt,
    required this.oneXTwo,
    required this.calibration,
    required this.competitions,
    required this.perCompetition,
    this.season,
    this.over25,
    this.btts,
    this.dnb,
    this.teamTotals,
  });

  factory EngineEvaluation.fromJson(Map<String, dynamic> j) {
    final details = _map(j['details']);
    final scope = _map(j['scope']);
    final per = _map(details['per_competition']);
    return EngineEvaluation(
      engineVersion: j['engine_version'] as String,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      season: scope['season'] is num ? (scope['season'] as num).toInt() : null,
      oneXTwo: Metrics(
        matches: _i(j['matches_evaluated']),
        brierModel: _d(j['brier_model']),
        brierBaseline: _d(j['brier_baseline']),
        loglossModel: _d(j['logloss_model']),
        loglossBaseline: _d(j['logloss_baseline']),
        accuracyModel: _d(j['accuracy_model']),
        accuracyBaseline: _dn(details['accuracy_baseline']),
      ),
      over25: details['over_2_5'] is Map
          ? Metrics.fromJson(_map(details['over_2_5']))
          : null,
      btts: details['btts'] is Map
          ? Metrics.fromJson(_map(details['btts']))
          : null,
      dnb:
          details['dnb'] is Map ? Metrics.fromJson(_map(details['dnb'])) : null,
      teamTotals: details['team_totals'] is Map
          ? Metrics.fromJson(_map(details['team_totals']))
          : null,
      calibration: [
        for (final b in (j['calibration'] as List? ?? const []))
          CalibrationBin(_d(b['from']), _d(b['to']), _i(b['count']),
              _d(b['predicted']), _d(b['observed'])),
      ],
      competitions: _strings(scope['competitions']),
      perCompetition: {
        for (final e in per.entries) e.key: Metrics.fromJson(_map(e.value))
      },
    );
  }

  final String engineVersion;
  final DateTime createdAt;
  final int? season;
  final Metrics oneXTwo;
  final Metrics? over25;
  final Metrics? btts;

  /// Remboursé si nul (matchs sans nul) et buts par équipe : présents dès la 0.29.
  final Metrics? dnb;
  final Metrics? teamTotals;
  final List<CalibrationBin> calibration;
  final List<String> competitions;
  final Map<String, Metrics> perCompetition;
}
