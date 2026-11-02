import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../simulator/data/stake_math.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Une ligne du carnet de paris (mise déclarée par l'utilisateur ; aucun pari n'est pris ici).
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.sourceType,
    required this.title,
    required this.stake,
    required this.totalOdd,
    required this.legs,
    required this.placedAt,
    required this.firstKickoffAt,
    this.sourceId,
    this.note,
    this.result,
    this.settledOdd,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'] as String,
        sourceType: j['source_type'] as String,
        sourceId: j['source_id'] as String?,
        title: j['title'] as String,
        stake: (j['stake'] as num).toInt(),
        totalOdd: (j['total_odd'] as num).toDouble(),
        legs: [
          for (final l in (j['legs'] as List? ?? const []))
            Map<String, dynamic>.from(l as Map)
        ],
        note: j['note'] as String?,
        placedAt: DateTime.parse(j['placed_at'] as String).toLocal(),
        firstKickoffAt:
            DateTime.parse(j['first_kickoff_at'] as String).toLocal(),
        result: j['result'] as String?,
        settledOdd: (j['settled_odd'] as num?)?.toDouble(),
      );

  final String id;
  final String sourceType;
  final String? sourceId;
  final String title;
  final int stake;
  final double totalOdd;
  final List<Map<String, dynamic>> legs;
  final String? note;
  final DateTime placedAt;
  final DateTime firstKickoffAt;
  final String? result;
  final double? settledOdd;

  bool get settled => result != null;

  /// Ce qui est revenu : mise × cote réglée si passé, mise rendue si annulé, 0 si perdu.
  int get returned => switch (result) {
        'won' => (stake * (settledOdd ?? totalOdd)).round(),
        'void' => stake,
        _ => 0,
      };

  /// Résultat net (0 tant que le pari n'est pas réglé).
  int get net => settled ? returned - stake : 0;

  /// Retour potentiel si tout passe.
  int get potential => (stake * totalOdd).round();
}

/// Bilan d'une période.
class JournalTotals {
  const JournalTotals(
      {required this.count,
      required this.staked,
      required this.returned,
      required this.pending,
      required this.pendingStake,
      required this.won,
      required this.lost});

  factory JournalTotals.of(Iterable<JournalEntry> list) {
    var count = 0, staked = 0, returned = 0, pending = 0, pendingStake = 0;
    var won = 0, lost = 0;
    for (final e in list) {
      count++;
      staked += e.stake;
      if (!e.settled) {
        pending++;
        pendingStake += e.stake;
      } else {
        returned += e.returned;
        if (e.result == 'won') won++;
        if (e.result == 'lost') lost++;
      }
    }
    return JournalTotals(
        count: count,
        staked: staked,
        returned: returned,
        pending: pending,
        pendingStake: pendingStake,
        won: won,
        lost: lost);
  }

  final int count;

  /// Total misé (réglé et en attente).
  final int staked;
  final int returned;
  final int pending;
  final int pendingStake;
  final int won;
  final int lost;

  /// Résultat net des paris réglés.
  int get net => returned - (staked - pendingStake);
}

/// Clé « 2026-11 » du mois local d'une date.
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

final _months = [
  'janvier',
  tr('février'),
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  tr('août'),
  'septembre',
  'octobre',
  'novembre',
  tr('décembre')
];

String monthLabel(String key) {
  final parts = key.split('-');
  final m = int.parse(parts[1]);
  return '${_months[m - 1][0].toUpperCase()}${_months[m - 1].substring(1)} ${parts[0]}';
}

/// Mois → lignes, du plus récent au plus ancien.
Map<String, List<JournalEntry>> byMonth(List<JournalEntry> list) {
  final out = <String, List<JournalEntry>>{};
  for (final e in list) {
    out.putIfAbsent(monthKey(e.placedAt), () => []).add(e);
  }
  final keys = out.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final k in keys) k: out[k]!};
}

/// Plafond par pari et budget mensuel choisis par l'utilisateur (jeu responsable).
class StakeLimits {
  const StakeLimits({this.stakeLimit, this.monthlyBudget});

  final int? stakeLimit;
  final int? monthlyBudget;
}

class JournalException implements Exception {
  const JournalException(this.message);
  final String message;
  @override
  String toString() => message;
}

class JournalRepository {
  JournalRepository(this._client);

  final SupabaseClient _client;

  Future<List<JournalEntry>> entries({int limit = 500}) async {
    if (_client.auth.currentUser == null) return const [];
    final rows = await _client
        .from('bet_journal')
        .select()
        .order('placed_at', ascending: false)
        .limit(limit);
    return rows.map(JournalEntry.fromJson).toList();
  }

  Future<String> add(SimInput input,
      {required int stake, required double odd, String? note}) async {
    try {
      final id = await _client.rpc('journal_add', params: {
        'p_source_type': input.sourceType,
        'p_source_id': input.sourceId,
        'p_title': input.title.length > 120
            ? input.title.substring(0, 120)
            : input.title,
        'p_stake': stake,
        'p_total_odd': odd,
        'p_legs': [
          for (final l in input.legs)
            {
              'match_id': l.matchId,
              'key': l.key,
              'odd': l.odd,
              'label': l.pick,
              'match': l.matchLabel,
            }
        ],
        'p_note': note,
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw JournalException(_message(e));
    }
  }

  Future<void> update(String id,
      {required int stake, required double odd, String? note}) async {
    try {
      await _client.rpc('journal_update', params: {
        'p_id': id,
        'p_stake': stake,
        'p_total_odd': odd,
        'p_note': note,
      });
    } on PostgrestException catch (e) {
      throw JournalException(_message(e));
    }
  }

  Future<void> delete(String id) =>
      _client.from('bet_journal').delete().eq('id', id);

  Future<StakeLimits> limits() async {
    final user = _client.auth.currentUser;
    if (user == null) return const StakeLimits();
    final row = await _client
        .from('user_preferences')
        .select('stake_limit, monthly_budget')
        .eq('user_id', user.id)
        .maybeSingle();
    return StakeLimits(
      stakeLimit: (row?['stake_limit'] as num?)?.toInt(),
      monthlyBudget: (row?['monthly_budget'] as num?)?.toInt(),
    );
  }

  Future<void> saveLimits(StakeLimits l) async {
    final user = _client.auth.currentUser;
    if (user == null) throw JournalException(tr('Session expirée'));
    await _client.from('user_preferences').update({
      'stake_limit': l.stakeLimit,
      'monthly_budget': l.monthlyBudget,
    }).eq('user_id', user.id);
  }

  static String _message(PostgrestException e) => switch (e.code) {
        '22023' || '54000' || 'P0002' => e.message,
        '42501' => tr('Connectez-vous pour tenir votre carnet.'),
        _ => tr('Enregistrement impossible pour le moment.'),
      };
}

final journalRepositoryProvider = Provider<JournalRepository>(
    (ref) => JournalRepository(ref.watch(supabaseClientProvider)));

final journalProvider = FutureProvider.autoDispose<List<JournalEntry>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(journalRepositoryProvider).entries();
});

final stakeLimitsProvider = FutureProvider.autoDispose<StakeLimits>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(journalRepositoryProvider).limits();
});
