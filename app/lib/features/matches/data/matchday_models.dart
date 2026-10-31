import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

class LineupPlayer {
  const LineupPlayer({required this.name, this.number, this.pos});

  factory LineupPlayer.fromJson(Map<String, dynamic> j) => LineupPlayer(
        name: j['name'] as String? ?? '?',
        number: (j['number'] as num?)?.toInt(),
        pos: j['pos'] as String?,
      );

  final String name;
  final int? number;
  final String? pos;
}

class TeamLineup {
  const TeamLineup({
    required this.teamId,
    required this.startXI,
    required this.substitutes,
    required this.fetchedAt,
    this.formation,
    this.coach,
  });

  factory TeamLineup.fromJson(Map<String, dynamic> j) => TeamLineup(
        teamId: (j['team_id'] as num).toInt(),
        formation: j['formation'] as String?,
        coach: j['coach'] as String?,
        startXI: [
          for (final p in (j['start_xi'] as List? ?? const []))
            LineupPlayer.fromJson(Map<String, dynamic>.from(p as Map))
        ],
        substitutes: [
          for (final p in (j['substitutes'] as List? ?? const []))
            LineupPlayer.fromJson(Map<String, dynamic>.from(p as Map))
        ],
        fetchedAt: DateTime.parse(j['fetched_at'] as String).toLocal(),
      );

  final int teamId;
  final String? formation;
  final String? coach;
  final List<LineupPlayer> startXI;
  final List<LineupPlayer> substitutes;
  final DateTime fetchedAt;
}

class Absence {
  const Absence(
      {required this.teamId,
      required this.player,
      required this.fetchedAt,
      this.type,
      this.reason});

  factory Absence.fromJson(Map<String, dynamic> j) => Absence(
        teamId: (j['team_id'] as num).toInt(),
        player: j['player_name'] as String,
        type: j['absence_type'] as String?,
        reason: j['reason'] as String?,
        fetchedAt: DateTime.parse(j['fetched_at'] as String).toLocal(),
      );

  final int teamId;
  final String player;
  final String? type;
  final String? reason;
  final DateTime fetchedAt;

  /// « Questionable » chez le fournisseur : présence incertaine.
  bool get uncertain => (type ?? '').toLowerCase().contains('question');
}

/// Motifs les plus fréquents du fournisseur, traduits ; sinon le texte d'origine.
String absenceReason(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'motif non précisé';
  const exact = {
    'injury': 'blessure',
    'knee injury': 'blessure au genou',
    'ankle injury': 'blessure à la cheville',
    'hamstring injury': 'blessure aux ischio-jambiers',
    'muscle injury': 'blessure musculaire',
    'thigh injury': 'blessure à la cuisse',
    'calf injury': 'blessure au mollet',
    'groin injury': 'blessure à l’aine',
    'back injury': 'blessure au dos',
    'foot injury': 'blessure au pied',
    'shoulder injury': 'blessure à l’épaule',
    'head injury': 'blessure à la tête',
    'knock': 'coup',
    'illness': 'maladie',
    'suspended': 'suspendu',
    'red card': 'suspendu (carton rouge)',
    'yellow cards': 'suspendu (cartons jaunes)',
    'international duty': 'sélection nationale',
    'personal reasons': 'raisons personnelles',
    'lack of fitness': 'manque de condition physique',
    'inactive': 'indisponible',
  };
  return exact[raw.trim().toLowerCase()] ?? raw.trim();
}

class Matchday {
  const Matchday({required this.lineups, required this.absences});

  final List<TeamLineup> lineups;
  final List<Absence> absences;

  TeamLineup? lineupOf(int teamId) {
    for (final l in lineups) {
      if (l.teamId == teamId) return l;
    }
    return null;
  }

  List<Absence> absencesOf(int teamId) => [
        for (final a in absences)
          if (a.teamId == teamId) a
      ];

  DateTime? get lastFetched {
    final all = [
      ...lineups.map((l) => l.fetchedAt),
      ...absences.map((a) => a.fetchedAt)
    ];
    return all.isEmpty ? null : all.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

final matchdayProvider =
    FutureProvider.autoDispose.family<Matchday, int>((ref, matchId) async {
  final client = ref.watch(supabaseClientProvider);
  final results = await Future.wait([
    client
        .from('match_lineups')
        .select('team_id, formation, coach, start_xi, substitutes, fetched_at')
        .eq('match_id', matchId),
    client
        .from('match_absences')
        .select('team_id, player_name, absence_type, reason, fetched_at')
        .eq('match_id', matchId)
        .order('player_name'),
  ]);
  return Matchday(
    lineups: results[0].map(TeamLineup.fromJson).toList(),
    absences: results[1].map(Absence.fromJson).toList(),
  );
});
