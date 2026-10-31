import 'package:flutter/material.dart';

import '../data/coupon_query.dart';

const _riskChoices = {
  'prudent': 'Prudent',
  'equilibre': 'Équilibré',
  'audacieux': 'Audacieux',
};

/// Barre « Trier / Filtrer » de l'écran Coupons, avec le nombre de coupons affichés.
class CouponQueryBar extends StatelessWidget {
  const CouponQueryBar({
    super.key,
    required this.query,
    required this.onChanged,
    required this.count,
  });

  final CouponQuery query;
  final ValueChanged<CouponQuery> onChanged;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = query.activeFilters;
    return Row(
      children: [
        Expanded(
          child: Text('$count coupon${count > 1 ? 's' : ''}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        PopupMenuButton<CouponSort>(
          tooltip: 'Trier',
          initialValue: query.sort,
          onSelected: (s) => onChanged(query.copyWith(sort: s)),
          itemBuilder: (_) => [
            for (final s in CouponSort.values)
              CheckedPopupMenuItem(
                  value: s, checked: s == query.sort, child: Text(s.label)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sort, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(query.sort == CouponSort.smart ? 'Trier' : 'Trié',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        Badge(
          isLabelVisible: active > 0,
          label: Text('$active'),
          child: TextButton.icon(
            onPressed: () async {
              final q = await showModalBottomSheet<CouponQuery>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => CouponFilterSheet(initial: query),
              );
              if (q != null) onChanged(q);
            },
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Filtrer'),
          ),
        ),
        if (active > 0)
          IconButton(
            tooltip: 'Effacer les filtres',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(query.cleared),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
          ),
      ],
    );
  }
}

/// Panneau de filtres : état, risque estimé, cote totale, période de publication.
class CouponFilterSheet extends StatefulWidget {
  const CouponFilterSheet({super.key, required this.initial});

  final CouponQuery initial;

  @override
  State<CouponFilterSheet> createState() => _CouponFilterSheetState();
}

class _CouponFilterSheetState extends State<CouponFilterSheet> {
  late CouponQuery _q = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtrer les coupons', style: theme.textTheme.titleLarge),
            title('État'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final s in CouponState.values)
                FilterChip(
                  label: Text(s.label),
                  selected: _q.states.contains(s),
                  onSelected: (on) => setState(() => _q = _q.copyWith(
                      states: on
                          ? {..._q.states, s}
                          : (_q.states.toSet()..remove(s)))),
                ),
            ]),
            title('Risque estimé'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in _riskChoices.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _q.risks.contains(e.key),
                  onSelected: (on) => setState(() => _q = _q.copyWith(
                      risks: on
                          ? {..._q.risks, e.key}
                          : (_q.risks.toSet()..remove(e.key)))),
                ),
            ]),
            title('Cote totale'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final r in OddRange.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: _q.oddRange == r,
                  onSelected: (_) =>
                      setState(() => _q = _q.copyWith(oddRange: r)),
                ),
            ]),
            title('Publiés depuis'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final (d, label) in const [
                (null, 'Toujours'),
                (1, '24 h'),
                (7, '7 jours'),
                (30, '30 jours'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _q.days == d,
                  onSelected: (_) =>
                      setState(() => _q = _q.copyWith(days: () => d)),
                ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _q = _q.cleared),
                  child: const Text('Réinitialiser'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _q),
                  child: const Text('Appliquer'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
