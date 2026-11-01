import 'package:flutter/material.dart';

import '../../analysis/data/analysis_format.dart';
import '../../assistant/data/assistant_models.dart';
import '../../coupons/data/coupon_models.dart';
import '../../lab/data/lab_repository.dart';
import '../../matches/data/sports_models.dart';
import '../data/stake_math.dart';
import 'stake_simulator_sheet.dart';

SimLeg _legOf(CouponSelection s, {double? current}) => SimLeg(
      matchId: s.match.id,
      key: s.key,
      matchLabel: '${s.match.home} – ${s.match.away}',
      pick: outcomeKeyLabel(s.key, s.match.home, s.match.away),
      odd: s.odd,
      kickoffAt: s.match.kickoffAt,
      currentOdd: current,
      probability: s.modelProbability,
    );

/// Coupon de la plateforme : cote et probabilité publiées, cotes actuelles si relevées.
SimInput couponSim(Coupon c, [Map<String, double> current = const {}]) =>
    SimInput(
      title: c.title,
      sourceType: 'coupon',
      sourceId: c.id,
      totalOdd: c.totalOdd,
      probability: c.combinedProbability,
      legs: [
        for (final s in c.selections)
          _legOf(s, current: current['${s.match.id}:${s.key}'])
      ],
    );

/// Coupon de l'utilisateur (assistant, laboratoire enregistré).
SimInput userCouponSim(UserCoupon c) => SimInput(
      title: c.title,
      sourceType: 'user_coupon',
      sourceId: c.id,
      totalOdd: c.totalOdd,
      probability: c.combinedProbability,
      legs: [for (final s in c.selections) _legOf(s)],
    );

/// Une issue d'un match (pronostic d'une analyse, ligne de marché).
SimInput singleSim(MatchSummary m,
        {required String key,
        required double odd,
        double? probability,
        String sourceType = 'analysis'}) =>
    SimInput(
      title: '${m.home.name} – ${m.away.name}',
      sourceType: sourceType,
      sourceId: '${m.id}',
      legs: [
        SimLeg(
          matchId: m.id,
          key: key,
          matchLabel: '${m.home.name} – ${m.away.name}',
          pick: outcomeKeyLabel(key, m.home.name, m.away.name),
          odd: odd,
          kickoffAt: m.kickoffAt,
          probability: probability,
        )
      ],
    );

/// Toutes les cotes relevées d'un match : une issue au choix dans le simulateur.
List<SimInput> oddsBoardSims(MatchSummary m, List<OddsLine> odds,
        {Map<String, double> probabilities = const {}}) =>
    [
      for (final o in odds)
        if (o.median > 1)
          singleSim(m,
              key: oddsKey(o),
              odd: o.median,
              probability: probabilities[oddsKey(o)],
              sourceType: 'match'),
    ];

/// Coupon en construction (laboratoire) : cotes indicatives.
SimInput manualSim(List<ManualPick> picks) => SimInput(
      title:
          'Mon coupon (${picks.length} sélection${picks.length > 1 ? 's' : ''})',
      sourceType: 'lab',
      legs: [
        for (final p in picks)
          SimLeg(
              matchId: p.matchId,
              key: p.key,
              matchLabel: p.matchLabel,
              pick: p.label,
              odd: p.odd)
      ],
    );

/// Bouton « Simuler une mise ».
class SimulateButton extends StatelessWidget {
  const SimulateButton(
      {super.key,
      required this.choices,
      this.initial = 0,
      this.filled = false});

  final List<SimInput> Function() choices;
  final int initial;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    void open() {
      final list = choices();
      if (list.isEmpty) return;
      showStakeSimulator(context, list, initial: initial);
    }

    const icon = Icon(Icons.calculate_outlined);
    const label = Text('Simuler une mise');
    return filled
        ? FilledButton.icon(onPressed: open, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: open, icon: icon, label: label);
  }
}
