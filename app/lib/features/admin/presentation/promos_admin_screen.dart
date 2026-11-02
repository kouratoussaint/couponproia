import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/form_widgets.dart';
import '../../billing/billing_screen.dart';
import '../../matches/data/sports_format.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

final promoScopes = {
  'all': tr('Tous les achats'),
  'subscription': tr('Forfaits'),
  'credits': tr('Crédits IA'),
};

String _day(DateTime d) => '${shortDate(d)}/${d.year}';

/// Codes promo : réduction en pourcentage, appliquée par le serveur au paiement,
/// une seule utilisation par compte, comptée quand le paiement est confirmé.
class PromosAdminScreen extends ConsumerWidget {
  const PromosAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(adminPromosProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Codes promo'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editPromo(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(tr('Nouveau code')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminPromosProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Text(
                tr('Le prix réduit est recalculé par le serveur au moment du paiement. Une utilisation est comptée quand le paiement est confirmé par l’opérateur.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            ...list.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [Text(adminErrorMessage(e))],
              data: (rows) => rows.isEmpty
                  ? [
                      Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(tr('Aucun code pour l’instant.')))
                    ]
                  : [
                      for (final p in rows)
                        Card(
                          child: ListTile(
                            leading: Icon(Icons.local_offer_outlined,
                                color: p['active'] == true
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline),
                            title: Text(
                                '${p['code']} · −${asInt(p['percent_off'])} %'),
                            subtitle: Text(_summary(p)),
                            isThreeLine: true,
                            trailing: Text(p['active'] == true
                                ? tr('Actif')
                                : tr('Inactif')),
                            onTap: () => editPromo(context, ref, p),
                          ),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  String _summary(Map<String, dynamic> p) {
    final plans = [for (final c in (p['plan_codes'] as List? ?? const [])) c];
    final ends = p['ends_at'] == null
        ? null
        : DateTime.parse(p['ends_at'] as String).toLocal();
    final max = p['max_uses'] == null ? '∞' : '${asInt(p['max_uses'])}';
    return [
      [
        promoScopes[p['applies_to']] ?? '${p['applies_to']}',
        if (plans.isNotEmpty) plans.join(', '),
        if (ends != null) trf('jusqu’au {0}', [_day(ends)]),
      ].join(' · '),
      trf('{0} / {1} utilisations · {2} de réduction',
          [asInt(p['uses']), max, fcfa(asInt(p['discount_total_xof']))]),
    ].join('\n');
  }
}

/// Création ou modification d'un code (le code lui-même n'est plus modifiable ensuite).
Future<void> editPromo(
    BuildContext context, WidgetRef ref, Map<String, dynamic>? existing) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: _PromoEditor(existing: existing),
    ),
  );
  if (saved == true) {
    ref.invalidate(adminPromosProvider);
    if (context.mounted) showMessage(context, tr('Code enregistré.'));
  }
}

class _PromoEditor extends ConsumerStatefulWidget {
  const _PromoEditor({this.existing});

  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_PromoEditor> createState() => _PromoEditorState();
}

class _PromoEditorState extends ConsumerState<_PromoEditor> {
  late final _code =
      TextEditingController(text: widget.existing?['code'] as String? ?? '');
  late final _description = TextEditingController(
      text: widget.existing?['description'] as String? ?? '');
  late final _percent = TextEditingController(
      text: widget.existing == null
          ? '10'
          : '${asInt(widget.existing!['percent_off'])}');
  late final _maxUses = TextEditingController(
      text: widget.existing?['max_uses'] == null
          ? ''
          : '${asInt(widget.existing!['max_uses'])}');
  late String _scope = widget.existing?['applies_to'] as String? ?? 'all';
  late final Set<String> _plans = {
    for (final c in (widget.existing?['plan_codes'] as List? ?? const []))
      c as String
  };
  late DateTime? _ends = widget.existing?['ends_at'] == null
      ? null
      : DateTime.parse(widget.existing!['ends_at'] as String).toLocal();
  late bool _active = widget.existing?['active'] as bool? ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    _percent.dispose();
    _maxUses.dispose();
    super.dispose();
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _ends ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d != null) {
      setState(() => _ends = DateTime(d.year, d.month, d.day, 23, 59));
    }
  }

  Future<void> _save() async {
    final percent = int.tryParse(_percent.text.trim());
    final maxText = _maxUses.text.trim();
    final maxUses = maxText.isEmpty ? null : int.tryParse(maxText);
    if (percent == null || percent < 1 || percent > 90) {
      setState(() => _error = tr('Réduction entre 1 et 90 %.'));
      return;
    }
    if (maxText.isNotEmpty && (maxUses == null || maxUses < 1)) {
      setState(() => _error = tr('Nombre d’utilisations invalide.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).savePromo(
            code: _code.text.trim().toUpperCase(),
            description: _description.text.trim(),
            percentOff: percent,
            appliesTo: _scope,
            planCodes: _scope == 'credits' ? const [] : _plans.toList(),
            startsAt: widget.existing?['starts_at'] == null
                ? null
                : DateTime.parse(widget.existing!['starts_at'] as String),
            endsAt: _ends,
            maxUses: maxUses,
            active: _active,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(publicSettingsProvider).valueOrNull ??
        const <String, dynamic>{};
    final paidPlans = [
      for (final p in (settings['pricing.plans'] as List? ?? const []))
        if (asInt(asMap(p)['monthly_xof']) > 0) asMap(p)['code'] as String,
    ];
    final editing = widget.existing != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                editing
                    ? trf('Modifier {0}', [widget.existing!['code']])
                    : tr('Nouveau code'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: !editing,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
                LengthLimitingTextInputFormatter(24),
              ],
              decoration: InputDecoration(
                  labelText: tr('Code'), helperText: tr('3 à 24 caractères')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLength: 200,
              decoration: InputDecoration(
                  labelText: tr('Description affichée (facultative)')),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _percent,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: tr('Réduction (%)')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxUses,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      labelText: tr('Utilisations max'),
                      hintText: tr('illimité')),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                for (final e in promoScopes.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            if (_scope != 'credits' && paidPlans.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(tr('Forfaits concernés (aucun = tous)'),
                  style: Theme.of(context).textTheme.bodySmall),
              Wrap(spacing: 8, children: [
                for (final c in paidPlans)
                  FilterChip(
                    label: Text(c.replaceAll('_', ' ')),
                    selected: _plans.contains(c),
                    onSelected: (v) =>
                        setState(() => v ? _plans.add(c) : _plans.remove(c)),
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_ends == null
                  ? tr('Sans date de fin')
                  : trf('Valable jusqu’au {0}', [_day(_ends!)])),
              trailing: _ends == null
                  ? TextButton(onPressed: _pickEnd, child: Text(tr('Choisir')))
                  : IconButton(
                      tooltip: tr('Retirer la date'),
                      onPressed: () => setState(() => _ends = null),
                      icon: const Icon(Icons.close)),
              onTap: _pickEnd,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Actif')),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(tr('Enregistrer')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Remboursement enregistré : l'argent est rendu depuis le tableau de bord de l'opérateur,
/// puis l'administrateur l'enregistre ici (forfait arrêté ou crédits restants retirés, journal).
Future<void> recordRefund(
    BuildContext context, WidgetRef ref, Map<String, dynamic> payment) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Enregistrer un remboursement')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(trf(
            '{0} · {1}\n\nRemboursez d’abord ce montant depuis le tableau de bord de l’agrégateur ({2}). Ici, {3}, et l’opération est inscrite au journal. Cette action est définitive.',
            [
              fcfa(asInt(payment['amount_xof'])),
              payment['transaction_id'],
              payment['provider'] == 'cinetpay' ? 'CinetPay' : 'LigdiCash',
              payment['kind'] == 'subscription'
                  ? tr('le forfait payé est arrêté')
                  : tr('les crédits encore disponibles de ce pack sont retirés')
            ])),
        const SizedBox(height: 8),
        TextField(
          controller: reason,
          decoration: InputDecoration(labelText: tr('Motif (journalisé)')),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Annuler'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Enregistrer'))),
      ],
    ),
  );
  final r = reason.text.trim();
  reason.dispose();
  if (ok != true) return;
  if (r.isEmpty) {
    if (context.mounted) {
      showMessage(context, tr('Le motif est obligatoire.'), error: true);
    }
    return;
  }
  try {
    final res = await ref
        .read(adminRepositoryProvider)
        .refundPayment(payment['id'] as String, r);
    ref.invalidate(adminPaymentsProvider);
    if (!context.mounted) return;
    final used = asInt(res['credits_already_used']);
    showMessage(
        context,
        payment['kind'] == 'subscription'
            ? trf('Remboursement enregistré : forfait {0}.',
                [res['subscription'] ?? tr('non trouvé')])
            : trf('Remboursement enregistré : {0} crédits retirés{1}.', [
                asInt(res['credits_removed']),
                used > 0 ? trf(' ({0} déjà utilisés)', [used]) : ''
              ]));
  } catch (e) {
    if (context.mounted) {
      showMessage(context, adminErrorMessage(e), error: true);
    }
  }
}
