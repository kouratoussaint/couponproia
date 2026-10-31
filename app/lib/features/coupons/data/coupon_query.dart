import 'coupon_models.dart';

/// Tri de la liste des coupons.
enum CouponSort {
  /// Défaut : coup d'envoi le plus proche pour les coupons en jeu, plus récents d'abord pour l'historique.
  smart('Recommandé'),
  kickoff('Coup d’envoi le plus proche'),
  recent('Publication la plus récente'),
  oddDesc('Cote la plus haute'),
  oddAsc('Cote la plus basse'),
  probabilityDesc('Probabilité estimée la plus haute'),
  selectionsAsc('Moins de sélections');

  const CouponSort(this.label);

  final String label;
}

/// État d'un coupon pour le filtre (les retirés sont un état à part).
enum CouponState {
  pending('En cours'),
  won('Gagnés'),
  lost('Perdus'),
  voided('Annulés'),
  withdrawn('Retirés');

  const CouponState(this.label);

  final String label;

  static CouponState of(Coupon c) {
    if (c.isWithdrawn) return CouponState.withdrawn;
    return switch (c.result) {
      'won' => CouponState.won,
      'lost' => CouponState.lost,
      'void' => CouponState.voided,
      _ => CouponState.pending,
    };
  }
}

/// Tranches de cote totale.
enum OddRange {
  any('Toutes'),
  low('Jusqu’à 2'),
  mid('2 à 5'),
  high('Plus de 5');

  const OddRange(this.label);

  final String label;

  bool accepts(double odd) => switch (this) {
        OddRange.any => true,
        OddRange.low => odd <= 2,
        OddRange.mid => odd > 2 && odd <= 5,
        OddRange.high => odd > 5,
      };
}

/// Tri et filtres de l'écran Coupons. Un ensemble vide signifie « tout ».
class CouponQuery {
  const CouponQuery({
    this.sort = CouponSort.smart,
    this.states = const {},
    this.risks = const {},
    this.oddRange = OddRange.any,
    this.days,
  });

  final CouponSort sort;
  final Set<CouponState> states;
  final Set<String> risks;
  final OddRange oddRange;

  /// Période de publication (jours) ; null = tout.
  final int? days;

  /// Nombre de filtres actifs (le tri n'en est pas un).
  int get activeFilters =>
      (states.isEmpty ? 0 : 1) +
      (risks.isEmpty ? 0 : 1) +
      (oddRange == OddRange.any ? 0 : 1) +
      (days == null ? 0 : 1);

  CouponQuery copyWith({
    CouponSort? sort,
    Set<CouponState>? states,
    Set<String>? risks,
    OddRange? oddRange,
    int? Function()? days,
  }) =>
      CouponQuery(
        sort: sort ?? this.sort,
        states: states ?? this.states,
        risks: risks ?? this.risks,
        oddRange: oddRange ?? this.oddRange,
        days: days == null ? this.days : days(),
      );

  CouponQuery get cleared => CouponQuery(sort: sort);

  bool accepts(Coupon c, DateTime now) {
    if (states.isNotEmpty && !states.contains(CouponState.of(c))) return false;
    if (risks.isNotEmpty && !risks.contains(c.riskLevel)) return false;
    if (!oddRange.accepts(c.totalOdd)) return false;
    if (days != null &&
        (c.publishedAt ?? c.publishAt)
            .isBefore(now.subtract(Duration(days: days!)))) {
      return false;
    }
    return true;
  }

  /// Comparateur ; [open] distingue la section « en jeu » pour le tri recommandé.
  int compare(Coupon a, Coupon b, {required bool open}) {
    final published =
        (b.publishedAt ?? b.publishAt).compareTo(a.publishedAt ?? a.publishAt);
    final byKickoff = a.firstKickoffAt.compareTo(b.firstKickoffAt);
    final primary = switch (sort) {
      CouponSort.smart => open ? byKickoff : published,
      CouponSort.kickoff => byKickoff,
      CouponSort.recent => published,
      CouponSort.oddDesc => b.totalOdd.compareTo(a.totalOdd),
      CouponSort.oddAsc => a.totalOdd.compareTo(b.totalOdd),
      CouponSort.probabilityDesc =>
        b.combinedProbability.compareTo(a.combinedProbability),
      CouponSort.selectionsAsc =>
        a.selections.length.compareTo(b.selections.length),
    };
    return primary != 0 ? primary : published;
  }

  /// Coupons filtrés et triés, séparés en « en jeu » et « historique ».
  ({List<Coupon> open, List<Coupon> past}) apply(List<Coupon> all,
      {String? category, required DateTime now}) {
    final kept = [
      for (final c in all)
        if ((category == null || c.category == category) && accepts(c, now)) c
    ];
    final open = kept.where((c) => c.isOpen(now) && !c.isWithdrawn).toList()
      ..sort((a, b) => compare(a, b, open: true));
    final past = kept.where((c) => !c.isOpen(now) || c.isWithdrawn).toList()
      ..sort((a, b) => compare(a, b, open: false));
    return (open: open, past: past);
  }
}
