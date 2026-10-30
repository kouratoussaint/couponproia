/// Modèles des coupons de la plateforme (écrits par le serveur, lus par l'app).
library;

double _d(Object? v) => (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
int _i(Object? v) => (v as num).toInt();
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

const categoryLabels = {
  'du_jour': 'Coupon du jour',
  'prudent': 'Prudent',
  'equilibre': 'Équilibré',
  'audacieux': 'Audacieux',
  'cote_elevee': 'Cote élevée',
  'multi_competitions': 'Multi-compétitions',
  'competition': 'Spécial compétition',
  'marche': 'Spécial marché',
  'strategie': 'Stratégie',
};

const riskLabels = {
  'prudent': 'Risque estimé : prudent',
  'equilibre': 'Risque estimé : équilibré',
  'audacieux': 'Risque estimé : audacieux',
};

const statusLabels = {
  'pending_review': 'À valider',
  'ready': 'Prêt, publication programmée',
  'published': 'Publié',
  'rejected': 'Rejeté',
  'expired': 'Expiré (non publié)',
  'withdrawn': 'Retiré',
};

class SelectionMatch {
  const SelectionMatch({
    required this.id,
    required this.kickoffAt,
    required this.status,
    required this.home,
    required this.away,
    required this.competition,
    this.homeLogo,
    this.awayLogo,
    this.homeGoals,
    this.awayGoals,
  });

  factory SelectionMatch.fromJson(Map<String, dynamic> j) => SelectionMatch(
        id: _i(j['id']),
        kickoffAt: _date(j['kickoff_at']),
        status: j['status'] as String,
        home: _map(j['home'])['name'] as String? ?? '?',
        away: _map(j['away'])['name'] as String? ?? '?',
        homeLogo: _map(j['home'])['logo_url'] as String?,
        awayLogo: _map(j['away'])['logo_url'] as String?,
        competition: _map(j['competition'])['name'] as String? ?? '',
        homeGoals: j['home_goals'] == null ? null : _i(j['home_goals']),
        awayGoals: j['away_goals'] == null ? null : _i(j['away_goals']),
      );

  final int id;
  final DateTime kickoffAt;
  final String status;
  final String home;
  final String away;
  final String? homeLogo;
  final String? awayLogo;
  final String competition;
  final int? homeGoals;
  final int? awayGoals;
}

class CouponSelection {
  const CouponSelection({
    required this.position,
    required this.match,
    required this.key,
    required this.odd,
    required this.oddsCapturedAt,
    required this.modelProbability,
    required this.reliability,
    required this.justification,
    this.oddBest,
    this.bookmakers,
    this.impliedProbability,
    this.edge,
    this.result,
  });

  factory CouponSelection.fromJson(Map<String, dynamic> j) => CouponSelection(
        position: _i(j['position']),
        match: SelectionMatch.fromJson(_map(j['match'])),
        key: j['selection_key'] as String,
        odd: _d(j['odd']),
        oddBest: _dn(j['odd_best']),
        bookmakers: j['bookmakers'] == null ? null : _i(j['bookmakers']),
        oddsCapturedAt: _date(j['odds_captured_at']),
        modelProbability: _d(j['model_probability']),
        impliedProbability: _dn(j['implied_probability']),
        edge: _dn(j['edge']),
        reliability: j['reliability'] as String? ?? 'faible',
        justification: j['justification'] as String? ?? '',
        result: j['result'] as String?,
      );

  final int position;
  final SelectionMatch match;
  final String key;

  /// Cote retenue à la génération (médiane des bookmakers) : jamais modifiée ensuite.
  final double odd;
  final double? oddBest;
  final int? bookmakers;
  final DateTime oddsCapturedAt;
  final double modelProbability;
  final double? impliedProbability;
  final double? edge;
  final String reliability;
  final String justification;
  final String? result;
}

class StatusChange {
  const StatusChange({required this.toStatus, required this.at, this.fromStatus, this.reason});

  factory StatusChange.fromJson(Map<String, dynamic> j) => StatusChange(
        fromStatus: j['from_status'] as String?,
        toStatus: j['to_status'] as String,
        reason: j['reason'] as String?,
        at: _date(j['created_at']),
      );

  final String? fromStatus;
  final String toStatus;
  final String? reason;
  final DateTime at;
}

class Coupon {
  const Coupon({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.riskLevel,
    required this.totalOdd,
    required this.combinedProbability,
    required this.status,
    required this.publishAt,
    required this.firstKickoffAt,
    required this.lastKickoffAt,
    required this.engineVersion,
    required this.dataSource,
    required this.summary,
    required this.vigilance,
    required this.createdAt,
    this.impliedProbability,
    this.statusNote,
    this.publishedAt,
    this.summaryFromAi = false,
    this.aiModel,
    this.marketNote,
    this.result,
    this.selections = const [],
    this.history = const [],
  });

  factory Coupon.fromJson(Map<String, dynamic> j) {
    final analysis = _map(j['analysis']);
    final selections = [
      for (final s in (j['coupon_selections'] as List? ?? const [])) CouponSelection.fromJson(_map(s)),
    ]..sort((a, b) => a.position.compareTo(b.position));
    final history = [
      for (final h in (j['coupon_status_history'] as List? ?? const [])) StatusChange.fromJson(_map(h)),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return Coupon(
      id: j['id'] as String,
      category: j['category'] as String,
      title: j['title'] as String,
      description: j['description'] as String? ?? '',
      riskLevel: j['risk_level'] as String,
      totalOdd: _d(j['total_odd']),
      combinedProbability: _d(j['combined_probability']),
      impliedProbability: _dn(j['implied_probability']),
      status: j['status'] as String,
      statusNote: j['status_note'] as String?,
      publishAt: _date(j['publish_at']),
      publishedAt: _dateOrNull(j['published_at']),
      firstKickoffAt: _date(j['first_kickoff_at']),
      lastKickoffAt: _date(j['last_kickoff_at']),
      engineVersion: j['engine_version'] as String,
      dataSource: j['data_source'] as String? ?? '',
      summary: analysis['analyse_generale'] as String? ?? '',
      vigilance: _strings(analysis['points_de_vigilance']),
      summaryFromAi: analysis['source'] == 'ia',
      aiModel: analysis['ai_model'] as String?,
      marketNote: analysis['market_note'] as String?,
      result: j['result'] as String?,
      createdAt: _date(j['created_at']),
      selections: selections,
      history: history,
    );
  }

  final String id;
  final String category;
  final String title;
  final String description;
  final String riskLevel;
  final double totalOdd;
  final double combinedProbability;
  final double? impliedProbability;
  final String status;
  final String? statusNote;
  final DateTime publishAt;
  final DateTime? publishedAt;
  final DateTime firstKickoffAt;
  final DateTime lastKickoffAt;
  final String engineVersion;
  final String dataSource;
  final String summary;
  final List<String> vigilance;
  final bool summaryFromAi;
  final String? aiModel;
  final String? marketNote;
  final String? result;
  final DateTime createdAt;
  final List<CouponSelection> selections;
  final List<StatusChange> history;

  bool get isWithdrawn => status == 'withdrawn';

  /// Encore « en jeu » : le dernier match n'est pas terminé depuis plus de 3 heures.
  bool isOpen(DateTime now) => lastKickoffAt.add(const Duration(hours: 3)).isAfter(now);
}

class CouponProfile {
  const CouponProfile({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.isActive,
    required this.mode,
    required this.publishMode,
    required this.generateTimes,
    required this.publishDelayMinutes,
    required this.criteria,
    this.description,
  });

  factory CouponProfile.fromJson(Map<String, dynamic> j) => CouponProfile(
        id: _i(j['id']),
        key: j['key'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        description: j['description'] as String?,
        isActive: j['is_active'] as bool,
        mode: j['mode'] as String,
        publishMode: j['publish_mode'] as String,
        generateTimes: _strings(j['generate_times']),
        publishDelayMinutes: _i(j['publish_delay_minutes']),
        criteria: _map(j['criteria']),
      );

  final int id;
  final String key;
  final String name;
  final String category;
  final String? description;
  final bool isActive;
  final String mode;
  final String publishMode;
  final List<String> generateTimes;
  final int publishDelayMinutes;
  final Map<String, dynamic> criteria;

  double? num(String k) => criteria[k] is num ? (criteria[k] as num).toDouble() : null;
}

class GenerationRun {
  const GenerationRun({
    required this.id,
    required this.profileName,
    required this.trigger,
    required this.status,
    required this.couponsCreated,
    required this.candidates,
    required this.reasons,
    required this.startedAt,
    this.slotKey,
  });

  factory GenerationRun.fromJson(Map<String, dynamic> j) => GenerationRun(
        id: _i(j['id']),
        profileName: _map(j['profile'])['name'] as String? ?? '?',
        trigger: j['trigger'] as String,
        slotKey: j['slot_key'] as String?,
        status: j['status'] as String,
        couponsCreated: _i(j['coupons_created']),
        candidates: _i(j['candidates']),
        reasons: _strings(j['reasons']),
        startedAt: _date(j['started_at']),
      );

  final int id;
  final String profileName;
  final String trigger;
  final String? slotKey;
  final String status;
  final int couponsCreated;
  final int candidates;
  final List<String> reasons;
  final DateTime startedAt;
}
