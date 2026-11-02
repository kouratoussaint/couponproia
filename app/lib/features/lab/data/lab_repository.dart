import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../matches/data/sports_models.dart';

double _d(Object? v) => (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Clé normalisée d'une issue (« 1X2.HOME », « OU.OVER.2.5 »), identique à celle du serveur.
String oddsKey(OddsLine o) {
  if (o.line == null) return '${o.marketCode}.${o.outcomeCode}';
  final l = o.line!;
  return '${o.marketCode}.${o.outcomeCode}.${l == l.roundToDouble() ? l.toStringAsFixed(0) : l}';
}

/// Sélection du coupon en construction (générateur manuel). La cote affichée est indicative :
/// le serveur la relit et recalcule tout au moment de l'enregistrement.
class ManualPick {
  const ManualPick(
      {required this.matchId,
      required this.key,
      required this.matchLabel,
      required this.label,
      required this.odd});

  final int matchId;
  final String key;
  final String matchLabel;
  final String label;
  final double odd;
}

class ManualCouponNotifier extends StateNotifier<List<ManualPick>> {
  ManualCouponNotifier() : super(const []);

  /// Ajoute l'issue ; une autre issue du même match la remplace ; la même issue la retire.
  void toggle(ManualPick pick) {
    final same = state.where((p) => p.matchId == pick.matchId).toList();
    if (same.any((p) => p.key == pick.key)) {
      state = state.where((p) => p.matchId != pick.matchId).toList();
    } else {
      state = [...state.where((p) => p.matchId != pick.matchId), pick];
    }
  }

  void remove(int matchId) =>
      state = state.where((p) => p.matchId != matchId).toList();

  void clear() => state = const [];

  void replaceAll(List<ManualPick> picks) => state = picks;
}

final manualCouponProvider =
    StateNotifierProvider<ManualCouponNotifier, List<ManualPick>>(
        (ref) => ManualCouponNotifier());

double indicativeOdd(List<ManualPick> picks) =>
    picks.fold(1.0, (p, x) => p * x.odd);

class LabException implements Exception {
  const LabException(this.message, [this.details = const [], this.code]);

  final String message;
  final List<String> details;

  /// Code d'erreur du serveur (« credits_required »…).
  final String? code;

  @override
  String toString() =>
      details.isEmpty ? message : '$message\n${details.join('\n')}';
}

class CouponSimulation {
  const CouponSimulation({
    required this.label,
    required this.runs,
    required this.probabilityAllCorrect,
    required this.distribution,
    required this.expectedCorrect,
    required this.simulatedWins,
    required this.winsLow,
    required this.winsHigh,
    required this.modelReturnPerUnit,
  });

  factory CouponSimulation.fromJson(Map<String, dynamic> j) => CouponSimulation(
        label: j['label'] as String,
        runs: _i(j['runs']),
        probabilityAllCorrect: _d(j['probability_all_correct']),
        distribution: [for (final x in j['distribution'] as List) _d(x)],
        expectedCorrect: _d(j['expected_correct']),
        simulatedWins: _i(j['simulated_wins']),
        winsLow: _i((j['wins_interval'] as List)[0]),
        winsHigh: _i((j['wins_interval'] as List)[1]),
        modelReturnPerUnit: _d(j['model_return_per_unit']),
      );

  final String label;
  final int runs;
  final double probabilityAllCorrect;
  final List<double> distribution;
  final double expectedCorrect;
  final int simulatedWins;
  final int winsLow;
  final int winsHigh;
  final double modelReturnPerUnit;
}

class Alternative {
  const Alternative({
    required this.replacePosition,
    required this.replaced,
    required this.matchId,
    required this.key,
    required this.selection,
    required this.match,
    required this.odd,
    required this.modelProbability,
    required this.newTotalOdd,
    required this.newCombinedProbability,
    required this.sameMatch,
  });

  factory Alternative.fromJson(Map<String, dynamic> j) => Alternative(
        replacePosition: _i(j['replace_position']),
        replaced: j['replaced'] as String,
        matchId: _i(j['match_id']),
        key: j['key'] as String,
        selection: j['selection'] as String,
        match: j['match'] as String,
        odd: _d(j['odd']),
        modelProbability: _d(j['model_probability']),
        newTotalOdd: _d(j['new_total_odd']),
        newCombinedProbability: _d(j['new_combined_probability']),
        sameMatch: j['kind'] == 'meme_match',
      );

  final int replacePosition;
  final String replaced;
  final int matchId;
  final String key;
  final String selection;
  final String match;
  final double odd;
  final double modelProbability;
  final double newTotalOdd;
  final double newCombinedProbability;
  final bool sameMatch;
}

class ComparisonRow {
  const ComparisonRow({
    required this.id,
    required this.title,
    required this.selections,
    required this.totalOdd,
    required this.combinedProbability,
    required this.competitions,
    required this.correlatedPairs,
    required this.lowReliability,
    required this.unvalidatedMarkets,
    this.impliedProbability,
    this.weakest,
  });

  factory ComparisonRow.fromJson(Map<String, dynamic> j) => ComparisonRow(
        id: j['id'] as String,
        title: j['title'] as String,
        selections: _i(j['selections']),
        totalOdd: _d(j['total_odd']),
        combinedProbability: _d(j['combined_probability']),
        impliedProbability: _dn(j['implied_probability']),
        competitions: _i(j['competitions']),
        correlatedPairs: _i(j['correlated_pairs']),
        lowReliability: _i(j['low_reliability']),
        unvalidatedMarkets: _i(j['unvalidated_markets']),
        weakest: j['weakest'] as String?,
      );

  final String id;
  final String title;
  final int selections;
  final double totalOdd;
  final double combinedProbability;
  final double? impliedProbability;
  final int competitions;
  final int correlatedPairs;
  final int lowReliability;
  final int unvalidatedMarkets;
  final String? weakest;
}

class LabRepository {
  LabRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('lab', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details is Map ? e.details as Map : const {};
      final errors =
          (d['errors'] as List?)?.map((x) => x.toString()).toList() ??
              const <String>[];
      throw LabException(
          switch (d['error']) {
            'invalid_selections' =>
              'Certaines sélections ne sont plus valides :',
            'too_many' => 'Douze sélections au maximum.',
            'feature_disabled' => 'Le Laboratoire est momentanément désactivé.',
            'coupon_not_found' => 'Coupon introuvable.',
            'need_two_coupons' =>
              'Choisissez au moins deux coupons à comparer.',
            'credits_required' =>
              'Crédits insuffisants : ce calcul coûte ${(d['cost'] as num?)?.toInt() ?? 1} crédit${((d['cost'] as num?)?.toInt() ?? 1) > 1 ? 's' : ''} '
                  'avec le forfait FREE. Achetez des crédits ou passez à un forfait payant.',
            _ => 'Le calcul a échoué. Réessayez dans un instant.',
          },
          errors,
          d['error']?.toString());
    }
  }

  /// Le serveur vérifie chaque sélection, relit les cotes et recalcule tout.
  Future<String> build(List<({int matchId, String key})> selections,
      {String? replaceCouponId, String? variantOf, bool save = true}) async {
    final data = await _call({
      'action': 'build',
      'selections': [
        for (final s in selections) {'match_id': s.matchId, 'key': s.key}
      ],
      if (replaceCouponId != null) 'coupon_id': replaceCouponId,
      if (variantOf != null) 'variant_of': variantOf,
      'save': save,
    });
    return data['coupon_id'] as String;
  }

  Future<Map<String, dynamic>> analyze(String couponId) async =>
      Map<String, dynamic>.from((await _call(
          {'action': 'analyze', 'coupon_id': couponId}))['diagnosis'] as Map);

  Future<List<Alternative>> optimize(String couponId) async {
    final data = await _call({'action': 'optimize', 'coupon_id': couponId});
    return [
      for (final a in data['alternatives'] as List)
        Alternative.fromJson(Map<String, dynamic>.from(a as Map))
    ];
  }

  Future<CouponSimulation> simulate(String couponId, {int runs = 1000}) async {
    final data = await _call(
        {'action': 'simulate', 'coupon_id': couponId, 'runs': runs});
    return CouponSimulation.fromJson(
        Map<String, dynamic>.from(data['simulation'] as Map));
  }

  Future<List<ComparisonRow>> compare(List<String> couponIds) async {
    final data = await _call({'action': 'compare', 'coupon_ids': couponIds});
    return [
      for (final r in data['comparison'] as List)
        ComparisonRow.fromJson(Map<String, dynamic>.from(r as Map))
    ];
  }
}

final labRepositoryProvider = Provider<LabRepository>(
    (ref) => LabRepository(ref.watch(supabaseClientProvider)));
