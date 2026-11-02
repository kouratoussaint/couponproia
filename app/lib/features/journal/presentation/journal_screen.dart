import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../simulator/data/stake_math.dart';
import '../../simulator/presentation/stake_simulator_sheet.dart';
import '../../system/system_providers.dart';
import '../data/journal_repository.dart';
import '../../help/help_screens.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Carnet de paris : les mises que l'utilisateur a déclarées, réglées automatiquement, avec son
/// bilan réel par mois et le suivi de son budget. Aucun pari n'est pris par l'application.
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(journalProvider);
    final limits = ref.watch(stakeLimitsProvider).valueOrNull;
    final cur = currencyLabel(ref.watch(publicSettingsProvider).valueOrNull);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Mon carnet de paris')),
        actions: [
          const HelpButton('carnet'),
          IconButton(
            tooltip: tr('Budget et plafond'),
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => context.push(AppRoutes.responsibleGaming),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(journalProvider);
          await ref.read(journalProvider.future);
        },
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: tr('Carnet indisponible'),
                body: userMessageFor(e)),
          ]),
          data: (list) {
            final months = byMonth(list);
            final thisMonth = monthKey(DateTime.now());
            final month = JournalTotals.of(months[thisMonth] ?? const []);
            final all = JournalTotals.of(list);
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                _MonthCard(
                    totals: month,
                    label: monthLabel(thisMonth),
                    budget: limits?.monthlyBudget,
                    currency: cur),
                if (list.isEmpty)
                  InfoMessage(
                    icon: Icons.menu_book_outlined,
                    title: tr('Votre carnet est vide'),
                    body: tr(
                        'Ouvrez un coupon, un match ou une analyse, touchez « Simuler une mise » puis « J’ai joué ce pari ». Le pari est réglé automatiquement après le match.'),
                  )
                else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: Text(tr('Depuis le début')),
                      subtitle: Text(trf(
                          '{0} paris · misé {1} · retourné {2}', [
                        all.count,
                        money(all.staked, currency: cur),
                        money(all.returned, currency: cur)
                      ])),
                      trailing: Text(signedMoney(all.net, currency: cur),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: all.net >= 0
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error)),
                    ),
                  ),
                  for (final MapEntry(key: k, value: rows)
                      in months.entries) ...[
                    SectionTitle(monthLabel(k),
                        trailing: Text(
                            signedMoney(JournalTotals.of(rows).net,
                                currency: cur),
                            style: theme.textTheme.labelLarge)),
                    for (final e in rows) _EntryTile(entry: e, currency: cur),
                  ],
                ],
                const SizedBox(height: 16),
                Text(
                  tr('Carnet personnel : seules vos mises déclarées y figurent, réglées sur le score à 90 minutes (un match annulé compte pour 1,00). Coupon Pro IA ne prend aucun pari. 18+ · Pariez de façon responsable.'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard(
      {required this.totals,
      required this.label,
      required this.budget,
      required this.currency});

  final JournalTotals totals;
  final String label;
  final int? budget;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio =
        budget == null || budget == 0 ? null : totals.staked / budget!;
    final barColor = ratio == null
        ? scheme.primary
        : ratio >= 1
            ? scheme.error
            : ratio >= 0.8
                ? BrandColors.orange
                : scheme.primary;
    Widget cell(String head, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(head,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Row(children: [
              cell(tr('Misé'), money(totals.staked, currency: currency)),
              cell(tr('Retourné'), money(totals.returned, currency: currency)),
              cell(tr('Net'), signedMoney(totals.net, currency: currency),
                  color: totals.net >= 0 ? scheme.primary : scheme.error),
            ]),
            if (totals.pending > 0) ...[
              const SizedBox(height: 8),
              Text(
                  trf('{0} pari{1} en attente ({2} misés)', [
                    totals.pending,
                    totals.pending > 1 ? 's' : '',
                    money(totals.pendingStake, currency: currency)
                  ]),
                  style: theme.textTheme.bodySmall),
            ],
            if (ratio != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: ratio.clamp(0, 1).toDouble(),
                    minHeight: 8,
                    color: barColor,
                    backgroundColor: barColor.withValues(alpha: 0.15)),
              ),
              const SizedBox(height: 6),
              Text(
                ratio >= 1
                    ? trf(
                        'Budget du mois atteint ({0}). Faire une pause est une bonne décision.',
                        [money(budget!, currency: currency)])
                    : trf('Budget du mois : {0} sur {1} ({2} %)', [
                        money(totals.staked, currency: currency),
                        money(budget!, currency: currency),
                        (ratio * 100).round()
                      ]),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: ratio >= 0.8 ? barColor : null,
                    fontWeight: ratio >= 0.8 ? FontWeight.w600 : null),
              ),
            ] else ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                onPressed: () => context.push(AppRoutes.responsibleGaming),
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: Text(tr('Fixer un budget mensuel')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.currency});

  final JournalEntry entry;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = entry;
    final (icon, color, label) = switch (e.result) {
      'won' => (Icons.check, scheme.primary, tr('Passé')),
      'lost' => (Icons.close, scheme.error, tr('Perdu')),
      'void' => (Icons.remove, scheme.outline, tr('Annulé')),
      _ => (Icons.schedule, scheme.onSurfaceVariant, tr('En attente')),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => _details(context, ref),
        leading: Semantics(
          label: label,
          child: CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, size: 18, color: color)),
        ),
        title: Text(trTitle(e.title),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(trf('Mise {0} · cote {1}\n{2}', [
          money(e.stake, currency: currency),
          decimal(e.totalOdd),
          dateTimeLabel(e.placedAt)
        ])),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
                e.settled
                    ? signedMoney(e.net, currency: '')
                    : money(e.potential, currency: ''),
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: e.settled ? color : scheme.onSurfaceVariant)),
            Text(e.settled ? label : tr('potentiel'),
                style: theme.textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _details(BuildContext context, WidgetRef ref) async {
    final e = entry;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(trTitle(e.title),
                  style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 6),
              for (final l in e.legs)
                Text(
                    '• ${l['match'] ?? ''}${(l['match'] ?? '') == '' ? '' : ' : '}${l['label'] ?? l['key']} (${decimal((l['odd'] as num).toDouble())})'),
              const SizedBox(height: 8),
              Text(trf('Mise {0} · cote obtenue {1} · {2}', [
                money(e.stake, currency: currency),
                decimal(e.totalOdd),
                e.settled
                    ? trf('retour {0}', [money(e.returned, currency: currency)])
                    : trf('retour potentiel {0}',
                        [money(e.potential, currency: currency)])
              ])),
              if (e.note != null) Text(trf('Note : {0}', [e.note])),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(sheet, 'edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr('Corriger')),
                  ),
                  if (e.sourceType == 'coupon' && e.sourceId != null)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(sheet, 'open'),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(tr('Voir le coupon')),
                    ),
                  if ((e.sourceType == 'match' || e.sourceType == 'analysis') &&
                      e.legs.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(sheet, 'match'),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(tr('Voir le match')),
                    ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(sheet).colorScheme.error),
                    onPressed: () => Navigator.pop(sheet, 'delete'),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr('Supprimer')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final repo = ref.read(journalRepositoryProvider);
    switch (action) {
      case 'open':
        await context.push(AppRoutes.couponDetailFor(e.sourceId!));
      case 'match':
        await context.push('/match/${e.legs.first['match_id']}');
      case 'edit':
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => JournalEntryDialog(
            title: e.title,
            stake: e.stake,
            odd: e.totalOdd,
            note: e.note,
            currency: currency,
            editing: true,
            onSave: (stake, odd, note) =>
                repo.update(e.id, stake: stake, odd: odd, note: note),
          ),
        );
        if (ok == true) ref.invalidate(journalProvider);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tr('Supprimer ce pari du carnet ?')),
            content: Text(tr('Il disparaîtra de votre bilan.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: Text(tr('Annuler'))),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: Text(tr('Supprimer'))),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await repo.delete(e.id);
          ref.invalidate(journalProvider);
        } catch (err) {
          if (context.mounted) {
            showMessage(context, userMessageFor(err), error: true);
          }
        }
    }
  }
}
