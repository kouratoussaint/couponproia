import 'package:flutter/material.dart';

import '../../../core/theme/brand_colors.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../data/coupon_models.dart';
import '../data/coupon_phase.dart';

/// Nom court d'un coupon : « Coupon du jour », « Cote élevée », « Opportunités du moment »
/// (le titre sans la date, déjà donnée par le contexte).
String couponName(Coupon c) => c.title.split(' · ').first;

/// Heure courte : « 14:30 » aujourd'hui, sinon « Demain 15:00 », « mar. 03/11 20:45 ».
String kickoffShort(DateTime t, DateTime now) => dateOnly(t) == dateOnly(now)
    ? timeLabel(t)
    : '${dayLabel(t, now)} ${timeLabel(t)}';

({String label, Color fg, Color bg}) riskStyle(
    BuildContext context, String risk) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final (label, fg) = switch (risk) {
    'prudent' => ('Prudent', theme.colorScheme.primary),
    'equilibre' => (
        'Équilibré',
        dark ? BrandColors.orange : const Color(0xFF8A5300)
      ),
    _ => ('Audacieux', theme.colorScheme.error),
  };
  return (label: label, fg: fg, bg: fg.withValues(alpha: 0.13));
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.fg, this.bg);

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: TextStyle(
                color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// Risque estimé, toujours affiché (même quand le nom du coupon le dit déjà).
class RiskTag extends StatelessWidget {
  const RiskTag(this.risk, {super.key});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final s = riskStyle(context, risk);
    return Semantics(
        label: 'Risque estimé : ${s.label.toLowerCase()}',
        child: ExcludeSemantics(child: _Tag(s.label, s.fg, s.bg)));
  }
}

/// Icône de chaque type de coupon.
IconData categoryIcon(String category) => switch (category) {
      'du_jour' => Icons.wb_sunny_outlined,
      'prudent' => Icons.shield_outlined,
      'equilibre' => Icons.balance,
      'audacieux' => Icons.local_fire_department_outlined,
      'cote_elevee' => Icons.trending_up,
      'multi_competitions' => Icons.public,
      'competition' => Icons.emoji_events_outlined,
      'marche' => Icons.query_stats,
      'strategie' => Icons.bolt,
      _ => Icons.receipt_long_outlined,
    };

/// Pastille carrée avec l'icône du type de coupon, teintée selon le risque estimé.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.coupon, {super.key, this.size = 40});

  final Coupon coupon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = riskStyle(context, coupon.riskLevel);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: s.bg, borderRadius: BorderRadius.circular(size * 0.3)),
        child:
            Icon(categoryIcon(coupon.category), size: size * 0.55, color: s.fg),
      ),
    );
  }
}

/// Onglets « À jouer · n », « En cours · n », « Résultats · n » (appui ; le balayage reste
/// réservé à la navigation principale).
class CouponTabs extends StatelessWidget {
  const CouponTabs(
      {super.key,
      required this.selected,
      required this.labels,
      required this.onSelected});

  final int selected;
  final List<String> labels;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: i == selected ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == selected
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 3,
                                offset: const Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelected(i),
                      child: SizedBox(
                        height: 40,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(labels[i],
                                  style: TextStyle(
                                      fontWeight: i == selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: i == selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cote en grand et probabilité estimée en dessous.
class _OddBlock extends StatelessWidget {
  const _OddBlock(this.c, {this.big = false});

  final Coupon c;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(decimal(c.totalOdd),
            style: (big
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text('${pct(c.combinedProbability)} estimé',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _LockedLine extends StatelessWidget {
  const _LockedLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Icon(Icons.lock_outline,
          size: 16, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Expanded(
        child: Text('Réservé aux forfaits payants jusqu’à la fin des matchs',
            style: theme.textTheme.bodySmall),
      ),
    ]);
  }
}

/// Coupon du jour mis en avant dans « À jouer », avec ses sélections.
class FeaturedCouponCard extends StatelessWidget {
  const FeaturedCouponCard(
      {super.key, required this.coupon, required this.onTap, this.onLongPress});

  final Coupon coupon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = coupon;
    final now = DateTime.now();
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryIcon(c, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(couponName(c).toUpperCase(),
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8)),
                            RiskTag(c.riskLevel),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            '${c.selections.isEmpty ? '' : '${c.selections.length} sélections · '}1er match ${kickoffShort(c.firstKickoffAt, now)}',
                            style: muted),
                      ],
                    ),
                  ),
                  _OddBlock(c, big: true),
                ],
              ),
              const Divider(height: 24),
              if (c.locked)
                const _LockedLine()
              else
                for (final s in c.selections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child:
                              Text(timeLabel(s.match.kickoffAt), style: muted),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${s.match.home} – ${s.match.away}',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                  outcomeKeyLabel(
                                      s.key, s.match.home, s.match.away),
                                  style: muted),
                            ],
                          ),
                        ),
                        Text(decimal(s.odd),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne compacte d'un coupon « À jouer » : nom, risque, sélections, heure, cote.
class CompactCouponTile extends StatelessWidget {
  const CompactCouponTile(
      {super.key, required this.coupon, required this.onTap, this.onLongPress});

  final Coupon coupon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = coupon;
    final now = DateTime.now();
    final teams = [for (final s in c.selections) s.match.home].join(', ');
    final meta = c.locked
        ? 'Réservé aux forfaits payants · ${kickoffShort(c.firstKickoffAt, now)}'
        : '${c.selections.length} sél. · ${kickoffShort(c.firstKickoffAt, now)}${teams.isEmpty ? '' : ' · $teams'}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CategoryIcon(c),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(couponName(c),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          RiskTag(c.riskLevel),
                          if (c.locked)
                            Icon(Icons.lock_outline,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _OddBlock(c),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icône d'état d'une sélection (validée, ratée, annulée, en direct, en attente, à venir).
class SelectionStateIcon extends StatelessWidget {
  const SelectionStateIcon(this.state, {super.key});

  final SelectionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final live = dark ? BrandColors.orange : const Color(0xFF8A5300);
    final (icon, color, label) = switch (state) {
      SelectionState.won => (Icons.check, scheme.primary, 'Validée'),
      SelectionState.lost => (Icons.close, scheme.error, 'Ratée'),
      SelectionState.voided => (Icons.remove, scheme.outline, 'Annulée'),
      SelectionState.live => (Icons.sensors, live, 'En direct'),
      SelectionState.awaiting => (
          Icons.hourglass_top,
          scheme.onSurfaceVariant,
          'Règlement en attente'
        ),
      SelectionState.pending => (
          Icons.schedule,
          scheme.onSurfaceVariant,
          'À venir'
        ),
    };
    return Semantics(
      label: label,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

/// Coupon « En cours » : progression et état de chaque sélection, score compris.
class LiveCouponCard extends StatelessWidget {
  const LiveCouponCard(
      {super.key, required this.coupon, required this.onTap, this.onLongPress});

  final Coupon coupon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = coupon;
    final now = DateTime.now();
    final p = progressOf(c);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final states = [for (final s in c.selections) selectionState(s)];
    final waiting = states.isNotEmpty &&
        states.every(
            (s) => s != SelectionState.pending && s != SelectionState.live);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryIcon(c),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(couponName(c),
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              RiskTag(c.riskLevel),
                            ]),
                        const SizedBox(height: 4),
                        Text(
                            'Publié ${kickoffShort(c.publishedAt ?? c.publishAt, now)}',
                            style: muted),
                      ],
                    ),
                  ),
                  _OddBlock(c, big: true),
                ],
              ),
              if (c.locked) ...[
                const SizedBox(height: 12),
                const _LockedLine(),
              ] else if (states.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < states.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: switch (states[i]) {
                              SelectionState.won => scheme.primary,
                              SelectionState.voided => scheme.outline,
                              SelectionState.live =>
                                (theme.brightness == Brightness.dark
                                    ? BrandColors.orange
                                    : const Color(0xFF8A5300)),
                              _ => scheme.outlineVariant,
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    waiting
                        ? 'Matchs terminés · règlement en cours'
                        : '${p.won} sélection${p.won > 1 ? 's' : ''} validée${p.won > 1 ? 's' : ''} sur ${p.total} · encore en jeu',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w600)),
                const Divider(height: 24),
                for (var i = 0; i < c.selections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SelectionStateIcon(states[i]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(scoreLine(c.selections[i].match),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                  '${outcomeKeyLabel(c.selections[i].key, c.selections[i].match.home, c.selections[i].match.away)} · cote ${decimal(c.selections[i].odd)}'
                                  '${states[i] == SelectionState.pending ? ' · ${kickoffShort(c.selections[i].match.kickoffAt, now)}' : ''}',
                                  style: muted),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// En-tête d'un jour de résultats : date et bilan, pertes comprises.
class ResultDayHeader extends StatelessWidget {
  const ResultDayHeader(this.day, {super.key});

  final ResultDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final label = dayLabel(day.day, now);
    final n = day.coupons.length;
    Widget count(int v, String word, Color color) => Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Column(children: [
            Text('$v',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, color: color)),
            Text(word, style: theme.textTheme.labelSmall),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      label.contains('/')
                          ? label
                          : '$label ${shortDate(day.day)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                      '$n coupon${n > 1 ? 's' : ''} décidé${n > 1 ? 's' : ''}, pertes comprises',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            count(day.won, day.won > 1 ? 'gagnés' : 'gagné', scheme.primary),
            count(day.lost, day.lost > 1 ? 'perdus' : 'perdu', scheme.error),
            if (day.voided > 0)
              count(day.voided, day.voided > 1 ? 'annulés' : 'annulé',
                  scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Ligne d'un coupon décidé : résultat, match décisif, cote.
class ResultCouponTile extends StatelessWidget {
  const ResultCouponTile(
      {super.key, required this.coupon, required this.onTap, this.onLongPress});

  final Coupon coupon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = coupon;
    final (icon, color, label) = switch (c.result) {
      'won' => (Icons.check, scheme.primary, 'Gagné'),
      'lost' => (Icons.close, scheme.error, 'Perdu'),
      _ => (Icons.remove, scheme.outline, 'Annulé'),
    };
    final detail = resultDetail(c);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Semantics(
                  label: label,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle),
                    child: Icon(icon, size: 18, color: color),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(categoryIcon(c.category),
                              size: 16,
                              color: riskStyle(context, c.riskLevel).fg),
                          Text(couponName(c),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          RiskTag(c.riskLevel),
                        ],
                      ),
                      if (detail.isNotEmpty)
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        decimal(c.result == 'won' && c.settledOdd != null
                            ? c.settledOdd!
                            : c.totalOdd),
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.result == 'won'
                                ? scheme.primary
                                : scheme.onSurfaceVariant)),
                    Text(label,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: color, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
