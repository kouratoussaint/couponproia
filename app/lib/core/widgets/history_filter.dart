import 'package:flutter/material.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Filtre d'historique : résultat (tout, gagnés, perdus, en cours) et période (7 j, 30 j, tout).
/// Les pertes ne sont jamais masquées par défaut.
enum ResultFilter { all, won, lost, pending }

class HistoryFilter {
  const HistoryFilter({this.result = ResultFilter.all, this.days});

  final ResultFilter result;

  /// null = toute la période.
  final int? days;

  HistoryFilter copyWith({ResultFilter? result, int? Function()? days}) =>
      HistoryFilter(
          result: result ?? this.result,
          days: days == null ? this.days : days());

  bool accepts(String? couponResult, DateTime date, {DateTime? now}) {
    final ok = switch (result) {
      ResultFilter.all => true,
      ResultFilter.won => couponResult == 'won',
      ResultFilter.lost => couponResult == 'lost',
      ResultFilter.pending => couponResult == null,
    };
    if (!ok) return false;
    if (days == null) return true;
    return date
        .isAfter((now ?? DateTime.now()).subtract(Duration(days: days!)));
  }
}

class HistoryFilterBar extends StatelessWidget {
  const HistoryFilterBar(
      {super.key, required this.value, required this.onChanged});

  final HistoryFilter value;
  final ValueChanged<HistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => onTap()),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (r, label) in [
            (ResultFilter.all, tr('Tout')),
            (ResultFilter.won, tr('Gagnés')),
            (ResultFilter.lost, tr('Perdus')),
            (ResultFilter.pending, tr('En cours')),
          ])
            chip(label, value.result == r,
                () => onChanged(value.copyWith(result: r))),
          const VerticalDivider(width: 16, indent: 10, endIndent: 10),
          for (final (d, label) in [
            (7, tr('7 j')),
            (30, tr('30 j')),
            (null, tr('Tout'))
          ])
            chip(label, value.days == d,
                () => onChanged(value.copyWith(days: () => d))),
        ],
      ),
    );
  }
}
