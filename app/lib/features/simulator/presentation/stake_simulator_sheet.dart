import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/root_messenger.dart';
import '../../analysis/data/analysis_format.dart';
import '../../journal/data/journal_repository.dart';
import '../../system/system_providers.dart';
import '../data/stake_math.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Ouvre le simulateur de mise. Plusieurs [choices] : l'utilisateur choisit l'issue à simuler
/// (fiche match) ; une seule : coupon, pronostic d'une analyse.
Future<void> showStakeSimulator(BuildContext context, List<SimInput> choices,
    {int initial = 0}) {
  assert(choices.isNotEmpty);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => StakeSimulatorSheet(
          choices: choices, initial: initial, controller: controller),
    ),
  );
}

/// Devise affichée (réglage public app.currency), « FCFA » par défaut.
String currencyLabel(Map<String, dynamic>? settings) {
  final c = settings?['app.currency'];
  return c is Map && c['label'] is String ? c['label'] as String : 'FCFA';
}

double withholdingPercent(Map<String, dynamic>? settings) {
  final v = settings?['simulator.withholding_percent'];
  return v is num ? v.toDouble().clamp(0, 50).toDouble() : 0;
}

class StakeSimulatorSheet extends ConsumerStatefulWidget {
  const StakeSimulatorSheet(
      {super.key, required this.choices, this.initial = 0, this.controller});

  final List<SimInput> choices;
  final int initial;
  final ScrollController? controller;

  @override
  ConsumerState<StakeSimulatorSheet> createState() =>
      _StakeSimulatorSheetState();
}

class _StakeSimulatorSheetState extends ConsumerState<StakeSimulatorSheet> {
  static const _quick = [500, 1000, 2000, 5000, 10000];
  late int _choice = widget.initial.clamp(0, widget.choices.length - 1);
  int _stake = 1000;
  final _field = TextEditingController(text: '1000');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _setStake(int v) {
    setState(() => _stake = v);
    final text = '$v';
    if (_field.text != text) {
      _field.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(publicSettingsProvider).valueOrNull;
    final cur = currencyLabel(settings);
    final tax = withholdingPercent(settings);
    final limits = ref.watch(stakeLimitsProvider).valueOrNull;
    final input = widget.choices[_choice];
    final odd = input.odd;
    final out = simulate(_stake, odd, withholdingPercent: tax);
    final current = input.currentOdd;
    final p = input.estimatedProbability;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    String m(num v) => money(v, currency: cur);

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            Icon(Icons.calculate_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Simulateur de mise'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(input.title, style: theme.textTheme.titleSmall),
        if (widget.choices.length > 1) ...[
          const SizedBox(height: 10),
          Text(tr('Issue à simuler'), style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, c) in widget.choices.indexed)
                ChoiceChip(
                  label: Text('${c.legs.first.pick} · ${decimal(c.odd)}'),
                  selected: i == _choice,
                  onSelected: (_) => setState(() => _choice = i),
                ),
            ],
          ),
        ] else
          for (final l in input.legs)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• ${l.matchLabel} : ${l.pick} (${decimal(l.odd)})',
                  style: muted),
            ),
        const SizedBox(height: 14),
        TextField(
          controller: _field,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: tr('Mise'),
            suffixText: cur,
            border: const OutlineInputBorder(),
          ),
          onChanged: (t) {
            final v = parseStake(t);
            if (v != null) setState(() => _stake = v);
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in _quick)
              ActionChip(
                label: Text(money(q, currency: '')),
                onPressed: () => _setStake(q),
                backgroundColor: q == _stake ? scheme.primaryContainer : null,
              ),
          ],
        ),
        if (limits?.stakeLimit case final limit? when _stake > limit)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Banner(
              icon: Icons.front_hand_outlined,
              color: BrandColors.orange,
              text: trf(
                  'Au-dessus de votre plafond par pari ({0}). Gardez la mise que vous aviez prévue.',
                  [m(limit)]),
            ),
          ),
        const SizedBox(height: 14),
        Card(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Retour potentiel si tout passe'),
                    style: theme.textTheme.labelLarge),
                Text(m(out.payout),
                    key: const Key('sim-payout'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: scheme.primary)),
                Text(trf('{0} × cote {1}', [m(_stake), decimal(odd)]),
                    style: muted),
                const Divider(height: 20),
                _Line(tr('Résultat net si tout passe'),
                    signedMoney(out.net, currency: cur),
                    color: scheme.primary),
                _Line(
                    input.legs.length > 1
                        ? tr('Si une seule sélection échoue')
                        : tr('Si le pronostic échoue'),
                    signedMoney(-_stake, currency: cur),
                    color: scheme.error),
                if (out.withholding > 0)
                  _Line(
                      trf('Prélèvement estimé de l’opérateur ({0} %)',
                          [decimal(tax)]),
                      '−${m(out.withholding)}'),
              ],
            ),
          ),
        ),
        if (current != null)
          Card(
            child: ListTile(
              leading: Icon(
                  current < odd ? Icons.trending_down : Icons.trending_up,
                  color: current < odd ? scheme.error : scheme.primary),
              title: Text(trf('Avec la cote actuelle {0}', [decimal(current)])),
              subtitle: Text(trf(
                  'Retour potentiel {0} (cote publiée {1}). Les cotes changent jusqu’au coup d’envoi.',
                  [
                    m(simulate(_stake, current, withholdingPercent: tax)
                        .payout),
                    decimal(odd)
                  ])),
            ),
          ),
        if (p != null) ...[
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('Lecture du modèle'),
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(trf(
                      'Probabilité estimée {0} : sur 100 {1} comparables, environ {2} passeraient selon le modèle.',
                      [
                        pct(p),
                        input.legs.length > 1 ? tr('coupons') : tr('paris'),
                        (p * 100).round()
                      ])),
                  const SizedBox(height: 4),
                  Builder(builder: (context) {
                    final ev =
                        expectedValue(_stake, odd, p, withholdingPercent: tax);
                    return Text(
                        trf('Valeur moyenne estimée de cette mise : {0}. {1}', [
                          signedMoney(ev, currency: cur),
                          ev < 0
                              ? tr('Sur la durée, l’opérateur garde sa marge.')
                              : tr('Estimation positive, pas une promesse.')
                        ]),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ev < 0 ? scheme.error : scheme.primary));
                  }),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(tr('Comparer plusieurs mises'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.2)
              },
              children: [
                TableRow(children: [
                  Text(tr('Mise'), style: theme.textTheme.labelMedium),
                  Text(tr('Retour'),
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.end),
                  Text(tr('Net'),
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.end),
                ]),
                for (final s in comparisonStakes(_stake))
                  () {
                    final o = simulate(s, odd, withholdingPercent: tax);
                    final bold = s == _stake
                        ? const TextStyle(fontWeight: FontWeight.w700)
                        : null;
                    return TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(money(s, currency: ''), style: bold),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(money(o.payout, currency: ''),
                            style: bold, textAlign: TextAlign.end),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(signedMoney(o.net, currency: ''),
                            style: bold?.copyWith(color: scheme.primary) ??
                                TextStyle(color: scheme.primary),
                            textAlign: TextAlign.end),
                      ),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
        if (input.legs.length > 1) ...[
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(tr('Si un match est annulé ou reporté')),
              subtitle: Text(tr('La sélection compte alors pour 1,00')),
              children: [
                for (final (i, l) in input.legs.indexed)
                  ListTile(
                    dense: true,
                    title: Text(l.matchLabel),
                    subtitle: Text(
                        trf('Cote {0}', [decimal(input.oddWithoutLeg(i))])),
                    trailing: Text(m(simulate(_stake, input.oddWithoutLeg(i),
                            withholdingPercent: tax)
                        .payout)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (ref.watch(currentUserProvider) != null)
          FilledButton.icon(
            onPressed: () => _addToJournal(input, cur),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(tr('J’ai joué ce pari : le noter dans mon carnet')),
          ),
        if (limits != null && limits.stakeLimit == null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push(AppRoutes.responsibleGaming);
            },
            icon: const Icon(Icons.shield_outlined),
            label: Text(tr('Fixer un plafond par pari et un budget mensuel')),
          ),
        const SizedBox(height: 8),
        Text(
          tr('Simulation indicative : retour = mise × cote, si toutes les sélections passent. Coupon Pro IA ne prend aucun pari. 18+ · Pariez de façon responsable.'),
          style: muted,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _addToJournal(SimInput input, String cur) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => JournalEntryDialog(
          title: input.title,
          stake: _stake,
          odd: input.currentOdd ?? input.odd,
          currency: cur,
          onSave: (stake, odd, note) => ref
              .read(journalRepositoryProvider)
              .add(input, stake: stake, odd: odd, note: note)),
    );
    if (saved != true || !mounted) return;
    ref.invalidate(journalProvider);
    final router = GoRouter.of(context);
    Navigator.pop(context);
    final messenger = rootMessengerKey.currentState;
    messenger?.showSnackBar(SnackBar(
      content: Text(tr('Pari noté dans votre carnet.')),
      action: SnackBarAction(
          label: tr('Voir'), onPressed: () => router.push(AppRoutes.journal)),
    ));
  }
}

/// Saisie (ou correction) de la mise et de la cote obtenue chez l'opérateur.
class JournalEntryDialog extends StatefulWidget {
  const JournalEntryDialog(
      {super.key,
      required this.title,
      required this.stake,
      required this.odd,
      required this.currency,
      required this.onSave,
      this.note,
      this.editing = false});

  final String title;
  final int stake;
  final double odd;
  final String currency;
  final String? note;
  final bool editing;
  final Future<void> Function(int stake, double odd, String? note) onSave;

  @override
  State<JournalEntryDialog> createState() => _JournalEntryDialogState();
}

class _JournalEntryDialogState extends State<JournalEntryDialog> {
  late final _stake = TextEditingController(text: '${widget.stake}');
  late final _odd = TextEditingController(
      text: widget.odd.toStringAsFixed(2).replaceAll('.', decimalSeparator));
  late final _note = TextEditingController(text: widget.note ?? '');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _stake.dispose();
    _odd.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stake = parseStake(_stake.text);
    final odd = double.tryParse(_odd.text.trim().replaceAll(',', '.'));
    if (stake == null) return setState(() => _error = tr('Mise invalide.'));
    if (odd == null || odd < 1.01 || odd > 1000000) {
      return setState(() => _error = tr('Cote invalide (au moins 1,01).'));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
          stake, odd, _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is JournalException
              ? e.message
              : tr('Enregistrement impossible pour le moment.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.editing
            ? tr('Corriger le pari')
            : tr('Noter dans mon carnet')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _stake,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: tr('Mise jouée'), suffixText: widget.currency),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _odd,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: tr('Cote obtenue chez votre opérateur')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                maxLength: 200,
                decoration: InputDecoration(labelText: tr('Note (facultatif)')),
              ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              Text(
                tr('Le carnet est personnel : réglé automatiquement sur le score à 90 minutes.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.editing ? tr('Enregistrer') : tr('Noter'))),
        ],
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
