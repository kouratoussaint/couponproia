/// Modèles de Mon Assistant IA : conversations, messages, coupons de l'utilisateur, crédits.
library;

import '../../coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double _d(Object? v) => (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};
List<String> _strings(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

class Credits {
  const Credits(
      {required this.plan,
      required this.total,
      required this.planCredits,
      required this.extraCredits,
      required this.unlimited});

  factory Credits.fromJson(Map<String, dynamic> j) => Credits(
        plan: j['plan'] as String? ?? 'FREE',
        total: _i(j['total']),
        planCredits: _i(j['plan_credits']),
        extraCredits: _i(j['extra_credits']),
        unlimited: j['unlimited'] == true,
      );

  final String plan;
  final int total;
  final int planCredits;
  final int extraCredits;
  final bool unlimited;

  String get label => unlimited
      ? tr('Illimité (équipe)')
      : trf('{0} crédit{1}', [total, total > 1 ? 's' : '']);
}

class Conversation {
  const Conversation(
      {required this.id, required this.title, required this.updatedAt});

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
      id: j['id'] as String,
      title: j['title'] as String,
      updatedAt: _date(j['updated_at']));

  final String id;
  final String title;
  final DateTime updatedAt;
}

class Opportunity {
  const Opportunity({
    required this.matchId,
    required this.match,
    required this.competition,
    required this.kickoffAt,
    required this.selection,
    required this.odd,
    required this.modelProbability,
    required this.reliability,
    this.impliedProbability,
    this.edge,
  });

  factory Opportunity.fromJson(Map<String, dynamic> j) => Opportunity(
        matchId: _i(j['match_id']),
        match: j['match'] as String,
        competition: j['competition'] as String? ?? '',
        kickoffAt: _date(j['kickoff_at']),
        selection: j['selection'] as String,
        odd: _d(j['odd']),
        modelProbability: _d(j['model_probability']),
        impliedProbability: _dn(j['implied_probability']),
        edge: _dn(j['edge']),
        reliability: j['reliability'] as String? ?? 'faible',
      );

  final int matchId;
  final String match;
  final String competition;
  final DateTime kickoffAt;
  final String selection;
  final double odd;
  final double modelProbability;
  final double? impliedProbability;
  final double? edge;
  final String reliability;
}

class Diagnosis {
  const Diagnosis(
      {required this.fragiles, required this.alerts, required this.quality});

  factory Diagnosis.fromJson(Map<String, dynamic> j) => Diagnosis(
        fragiles: [
          for (final f in (j['fragiles'] as List? ?? const []))
            '${_map(f)['selection']} : ${_map(f)['raison']}',
        ],
        alerts: _strings(j['alertes']),
        quality: _strings(j['qualite']),
      );

  final List<String> fragiles;
  final List<String> alerts;
  final List<String> quality;
}

class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.intent,
    this.couponIds = const [],
    this.warnings = const [],
    this.opportunities = const [],
    this.diagnosis,
    this.creditsCharged = 0,
  });

  factory AssistantMessage.fromJson(Map<String, dynamic> j) {
    final payload = _map(j['payload']);
    return AssistantMessage(
      id: j['id'] as String,
      role: j['role'] as String,
      content: j['content'] as String,
      intent: j['intent'] as String?,
      createdAt: _date(j['created_at']),
      couponIds: _strings(payload['coupon_ids']),
      warnings: _strings(payload['warnings']),
      opportunities: [
        for (final o in (payload['opportunities'] as List? ?? const []))
          Opportunity.fromJson(_map(o))
      ],
      diagnosis: payload['diagnosis'] is Map
          ? Diagnosis.fromJson(_map(payload['diagnosis']))
          : null,
      creditsCharged: _i(j['credits_charged']),
    );
  }

  final String id;
  final String role;
  final String content;
  final String? intent;
  final DateTime createdAt;
  final List<String> couponIds;
  final List<String> warnings;
  final List<Opportunity> opportunities;
  final Diagnosis? diagnosis;
  final int creditsCharged;

  bool get isUser => role == 'user';
}

/// Coupon de l'utilisateur (proposition de l'assistant, puis coupon enregistré).
class UserCoupon {
  const UserCoupon({
    required this.id,
    required this.status,
    required this.title,
    required this.totalOdd,
    required this.combinedProbability,
    required this.riskLevel,
    required this.engineVersion,
    required this.createdAt,
    required this.selections,
    required this.summary,
    required this.vigilance,
    required this.warnings,
    this.impliedProbability,
    this.conversationId,
    this.summaryFromAi = false,
    this.result,
    this.settledOdd,
    this.publishedAt,
    this.settledAt,
    this.manual = false,
    this.variantOf,
  });

  factory UserCoupon.fromJson(Map<String, dynamic> j) {
    final analysis = _map(j['analysis']);
    return UserCoupon(
      id: j['id'] as String,
      status: j['status'] as String,
      title: j['title'] as String,
      totalOdd: _d(j['total_odd']),
      combinedProbability: _d(j['combined_probability']),
      impliedProbability: _dn(j['implied_probability']),
      riskLevel: j['risk_level'] as String,
      engineVersion: j['engine_version'] as String,
      conversationId: j['conversation_id'] as String?,
      createdAt: _date(j['created_at']),
      selections: [
        for (final s in (j['user_coupon_selections'] as List? ?? const []))
          CouponSelection.fromJson(_map(s)),
      ]..sort((a, b) => a.position.compareTo(b.position)),
      summary: analysis['analyse_generale'] as String? ?? '',
      vigilance: _strings(analysis['points_de_vigilance']),
      warnings: _strings(analysis['warnings']),
      summaryFromAi: analysis['source'] == 'ia',
      result: j['result'] as String?,
      settledOdd: _dn(j['settled_odd']),
      publishedAt: j['published_at'] == null ? null : _date(j['published_at']),
      settledAt: j['settled_at'] == null ? null : _date(j['settled_at']),
      manual: analysis['manual'] == true,
      variantOf: analysis['variant_of'] as String?,
    );
  }

  final String id;
  final String status;
  final String title;
  final double totalOdd;
  final double combinedProbability;
  final double? impliedProbability;
  final String riskLevel;
  final String engineVersion;
  final String? conversationId;
  final DateTime createdAt;
  final List<CouponSelection> selections;
  final String summary;
  final List<String> vigilance;
  final List<String> warnings;
  final bool summaryFromAi;
  final String? result;
  final double? settledOdd;

  /// Publié sur le profil Tipster : immuable.
  final DateTime? publishedAt;

  /// Date du règlement (gagné, perdu, annulé).
  final DateTime? settledAt;

  /// Composé à la main dans le laboratoire.
  final bool manual;

  /// Version optimisée de ce coupon (laboratoire).
  final String? variantOf;

  bool get isSaved => status == 'saved';
  bool get isPublished => publishedAt != null;
}

/// Texte partageable d'un coupon (copié dans le presse-papiers).
String couponShareText(String title, double totalOdd,
    List<CouponSelection> selections, String Function(CouponSelection) label) {
  final lines = [
    title,
    for (final s in selections)
      '• ${s.match.home} – ${s.match.away} : ${label(s)} @ ${s.odd.toStringAsFixed(2).replaceAll('.', decimalSeparator)}',
    trf('Cote totale : {0}',
        [totalOdd.toStringAsFixed(2).replaceAll('.', decimalSeparator)]),
    tr('Estimations de Coupon Pro IA, sans garantie de gain. Pariez de façon responsable.'),
  ];
  return lines.join('\n');
}
