import '../../matches/data/sports_format.dart';
import 'coupon_models.dart';

/// Onglet d'un coupon de la plateforme.
/// - À jouer : aucun match n'a commencé ;
/// - En cours : au moins un match a commencé, rien n'est encore décidé ;
/// - Résultats : décidé par le serveur (gagné, perdu, annulé), même s'il reste des matchs ;
/// - Retiré : à part, grisé, en bas des résultats.
enum CouponPhase { toPlay, live, decided, withdrawn }

CouponPhase phaseOf(Coupon c, DateTime now) {
  if (c.isWithdrawn) return CouponPhase.withdrawn;
  if (c.result != null) return CouponPhase.decided;
  return now.isBefore(c.firstKickoffAt) ? CouponPhase.toPlay : CouponPhase.live;
}

/// État d'une sélection pour l'affichage.
enum SelectionState { won, lost, voided, live, awaiting, pending }

SelectionState selectionState(CouponSelection s) => switch (s.result) {
      'won' => SelectionState.won,
      'lost' => SelectionState.lost,
      'void' => SelectionState.voided,
      _ => switch (s.match.status) {
          'live' || 'interrupted' => SelectionState.live,
          // Match terminé, règlement pas encore passé (toutes les 30 min).
          'finished' || 'awarded' => SelectionState.awaiting,
          _ => SelectionState.pending,
        },
    };

String scoreLine(SelectionMatch m) => m.homeGoals != null && m.awayGoals != null
    ? '${m.home} ${m.homeGoals}–${m.awayGoals} ${m.away}'
    : '${m.home} – ${m.away}';

/// « Raté : Chelsea 2–0 Manchester United · +1 », « Toutes validées », « Annulé ».
String resultDetail(Coupon c) {
  if (c.locked || c.selections.isEmpty) return '';
  final lost = c.selections.where((s) => s.result == 'lost').toList();
  return switch (c.result) {
    'won' => 'Toutes les sélections validées',
    'void' => 'Annulé (match reporté ou annulé)',
    _ when lost.isNotEmpty =>
      'Raté : ${scoreLine(lost.first.match)}${lost.length > 1 ? ' · +${lost.length - 1}' : ''}',
    _ => '',
  };
}

/// Progression d'un coupon en cours : sélections validées sur le total.
({int won, int total}) progressOf(Coupon c) => (
      won: c.selections.where((s) => s.result == 'won').length,
      total: c.selections.length,
    );

/// Jour auquel un coupon a été décidé (pour grouper les résultats).
DateTime decidedDay(Coupon c) => dateOnly(c.settledAt ?? c.lastKickoffAt);

class ResultDay {
  ResultDay(this.day, this.coupons);

  final DateTime day;
  final List<Coupon> coupons;

  int get won => coupons.where((c) => c.result == 'won').length;
  int get lost => coupons.where((c) => c.result == 'lost').length;
  int get voided => coupons.where((c) => c.result == 'void').length;
}

/// Résultats groupés par jour, du plus récent au plus ancien.
List<ResultDay> groupByDay(List<Coupon> decided) {
  final byDay = <DateTime, List<Coupon>>{};
  for (final c in decided) {
    byDay.putIfAbsent(decidedDay(c), () => []).add(c);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      ResultDay(
          d,
          byDay[d]!
            ..sort((a, b) => (b.settledAt ?? b.lastKickoffAt)
                .compareTo(a.settledAt ?? a.lastKickoffAt)))
  ];
}

/// Tri de l'onglet « À jouer ».
enum ToPlaySort {
  kickoff('Coup d’envoi'),
  oddDesc('Cote la plus haute'),
  probabilityDesc('Probabilité la plus haute'),
  recent('Plus récents');

  const ToPlaySort(this.label);

  final String label;

  int compare(Coupon a, Coupon b) => switch (this) {
        ToPlaySort.kickoff => a.firstKickoffAt.compareTo(b.firstKickoffAt),
        ToPlaySort.oddDesc => b.totalOdd.compareTo(a.totalOdd),
        ToPlaySort.probabilityDesc =>
          b.combinedProbability.compareTo(a.combinedProbability),
        ToPlaySort.recent => (b.publishedAt ?? b.publishAt)
            .compareTo(a.publishedAt ?? a.publishAt),
      };
}

/// Filtre de l'onglet « Résultats ».
enum ResultKind {
  all('Tous', null),
  won('Gagnés', 'won'),
  lost('Perdus', 'lost'),
  voided('Annulés', 'void');

  const ResultKind(this.label, this.result);

  final String label;
  final String? result;

  bool accepts(Coupon c) => result == null || c.result == result;
}

/// Période affichée dans « Résultats » (jours ; 0 = tout l'historique).
/// Pas de clé nulle : un menu Flutter traite une valeur nulle comme une annulation.
const resultPeriods = <int, String>{7: '7 jours', 30: '30 jours', 0: 'Tout'};

/// Les trois listes de l'écran, triées.
({List<Coupon> toPlay, List<Coupon> live}) splitActive(
    List<Coupon> active, DateTime now,
    {String? category, ToPlaySort sort = ToPlaySort.kickoff}) {
  final kept = [
    for (final c in active)
      if (category == null || c.category == category) c
  ];
  final toPlay = kept
      .where((c) => phaseOf(c, now) == CouponPhase.toPlay)
      .toList()
    ..sort(sort.compare);
  final live = kept.where((c) => phaseOf(c, now) == CouponPhase.live).toList()
    ..sort((a, b) => a.lastKickoffAt.compareTo(b.lastKickoffAt));
  return (toPlay: toPlay, live: live);
}

List<Coupon> filterDecided(List<Coupon> decided, DateTime now,
        {String? category, ResultKind kind = ResultKind.all, int days = 0}) =>
    [
      for (final c in decided)
        if ((category == null || c.category == category) &&
            kind.accepts(c) &&
            (days == 0 ||
                !decidedDay(c).isBefore(
                    dateOnly(now).subtract(Duration(days: days - 1)))))
          c
    ];
