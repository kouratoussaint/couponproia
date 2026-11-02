import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../../analysis/data/analysis_models.dart';
import '../../analysis/presentation/analysis_section.dart';
import '../../matches/presentation/sports_widgets.dart';

import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../data/coupon_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Pastille de risque estimé (jamais présentée comme une garantie).
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.risk, this.compact = false});

  final String risk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (risk) {
      'prudent' => scheme.primary,
      'equilibre' => BrandColors.orange,
      _ => scheme.error,
    };
    final text = compact
        ? {
              'prudent': tr('Prudent'),
              'equilibre': tr('Équilibré'),
              'audacieux': tr('Audacieux')
            }[risk] ??
            risk
        : riskLabels[risk] ?? risk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Résultat réglé d'un coupon ou d'une sélection (gagné, perdu, annulé) ou « en cours ».
class ResultBadge extends StatelessWidget {
  const ResultBadge({super.key, required this.result, this.odd});

  final String? result;
  final double? odd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (result) {
      'won' => (scheme.primary, Icons.check_circle),
      'lost' => (scheme.error, Icons.cancel),
      'void' => (scheme.outline, Icons.remove_circle_outline),
      _ => (scheme.onSurfaceVariant, Icons.schedule),
    };
    final label = result == null
        ? tr('En cours')
        : '${resultLabels[result] ?? result}${result == 'won' && odd != null ? ' · ${decimal(odd!)}' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

/// « Aujourd’hui 31/10 », « jeu. 29/10 » : la date n'est ajoutée qu'aux jours relatifs
/// (dayLabel contient déjà la date pour les autres jours).
String dayWithDate(DateTime local, DateTime now) {
  final label = dayLabel(local, now);
  return label.contains('/') ? label : '$label ${shortDate(local)}';
}

String couponDateLabel(DateTime local, DateTime now) =>
    '${dayWithDate(local, now)} · ${timeLabel(local)}';

class CouponCard extends StatelessWidget {
  const CouponCard(
      {super.key,
      required this.coupon,
      required this.onTap,
      this.onLongPress,
      this.trailing});

  final Coupon coupon;
  final VoidCallback onTap;

  /// Appui long : menu d'actions (partager, copier, visuel, actions d'équipe).
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Niveaux de gris : un coupon retiré reste visible (transparence) mais se distingue nettement.
  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = coupon;
    final now = DateTime.now();
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(categoryLabels[c.category] ?? c.category,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                  if (c.result != null && !c.isWithdrawn)
                    ResultBadge(result: c.result, odd: c.settledOdd)
                  else if (c.isWithdrawn)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.block,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(tr('Retiré'),
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700)),
                    ])
                  else
                    RiskBadge(risk: c.riskLevel, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(trTitle(c.title), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (c.locked)
                Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          tr('Réservé aux forfaits payants jusqu’à la fin des matchs'),
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              for (final s in c.selections.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${s.match.home} – ${s.match.away} · ${outcomeKeyLabel(s.key, s.match.home, s.match.away)}',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (c.selections.length > 4)
                Text(trf('+ {0} autre(s)', [c.selections.length - 4]),
                    style: theme.textTheme.bodySmall),
              const Divider(height: 18),
              // Passe sur deux lignes si l'écran est étroit ou le texte agrandi.
              Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(trf('Cote {0}', [decimal(c.totalOdd)]),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: theme.colorScheme.primary)),
                      Text(trf('Estimation {0}', [pct(c.combinedProbability)]),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  trailing ??
                      Text(
                        trf('Début {0}',
                            [couponDateLabel(c.firstKickoffAt, now)]),
                        style: theme.textTheme.labelSmall,
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!c.isWithdrawn) return card;
    return Semantics(
      label: tr('Coupon retiré'),
      child: Opacity(
          opacity: 0.6,
          child: ColorFiltered(colorFilter: _greyscale, child: card)),
    );
  }
}

/// Carte d'une sélection : match, issue, cote conservée, probabilités, fiabilité, justification.
class SelectionCard extends StatelessWidget {
  const SelectionCard({super.key, required this.selection, this.currentOdd});

  final CouponSelection selection;
  final double? currentOdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = selection;
    final m = s.match;
    final now = DateTime.now();
    final played =
        m.homeGoals != null && m.awayGoals != null && m.status != 'scheduled';
    final changed = currentOdd != null && (currentOdd! - s.odd).abs() >= 0.01;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.matchDetailFor(m.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                trf('{0} · {1} à {2}', [
                  m.competition,
                  dayWithDate(m.kickoffAt, now),
                  timeLabel(m.kickoffAt)
                ]),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SportsLogo(url: m.homeLogo, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      played
                          ? '${m.home} ${m.homeGoals}-${m.awayGoals} ${m.away}'
                          : '${m.home} – ${m.away}',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SportsLogo(url: m.awayLogo, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(outcomeKeyLabel(s.key, m.home, m.away),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (s.result != null) ...[
                    ResultBadge(result: s.result),
                    const SizedBox(width: 8),
                  ],
                  Text(decimal(s.odd),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ReliabilityChip(
                      reliability: Reliability.parse(s.reliability)),
                  Text(trf('Estimation {0}', [pct(s.modelProbability)]),
                      style: theme.textTheme.labelMedium),
                  if (s.impliedProbability != null)
                    Text(trf('Marché {0}', [pct(s.impliedProbability!)]),
                        style: theme.textTheme.labelMedium),
                  if (s.edge != null)
                    Text(
                      trf('Écart {0}', [edgePoints(s.edge!)]),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: s.edge! > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(s.justification, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                trf('Cote médiane de {0} bookmakers relevée le {1} à {2}{3}', [
                  s.bookmakers ?? '?',
                  shortDate(s.oddsCapturedAt),
                  timeLabel(s.oddsCapturedAt),
                  changed
                      ? trf(
                          ' · cote actuelle {0} (la cote publiée est conservée)',
                          [decimal(currentOdd!)])
                      : ''
                ]),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenu d'un coupon réservé : visible avec un forfait payant, ou au forfait FREE après les matchs.
class LockedCouponNotice extends StatelessWidget {
  const LockedCouponNotice({super.key, required this.lastKickoffAt});

  /// Coup d'envoi du dernier match : le coupon s'ouvre au forfait FREE 2 h 15 plus tard.
  final DateTime lastKickoffAt;

  DateTime get openAt =>
      lastKickoffAt.add(const Duration(hours: 2, minutes: 15));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr('Coupon réservé'),
                        style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trf('Les sélections et l’analyse de ce coupon sont accessibles à tout moment avec un forfait payant. Avec le forfait FREE, elles deviennent visibles après les matchs (vers {0} à {1}).',
                  [shortDate(openAt), timeLabel(openAt)]),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.billing),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: Text(tr('Voir les forfaits')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
