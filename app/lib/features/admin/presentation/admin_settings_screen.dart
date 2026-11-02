import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/form_widgets.dart';
import '../../billing/billing_screen.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import 'payment_providers_card.dart';
import '../data/admin_repository.dart';
import 'promos_admin_screen.dart';
import 'users_admin_screen.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

String _when(String? iso) {
  if (iso == null) return '–';
  final d = DateTime.parse(iso).toLocal();
  return '${shortDate(d)}/${d.year} ${timeLabel(d)}';
}

/// Modules (feature flags) : effet immédiat, sans nouvelle version.
class FlagsAdminScreen extends ConsumerWidget {
  const FlagsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(adminFlagsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Modules'))),
      body: flags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Indisponible'),
            body: adminErrorMessage(e)),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Text(
                tr('Chaque changement s’applique tout de suite à toutes les apps et est inscrit au journal.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final f in list)
              Card(
                child: SwitchListTile(
                  title: Text(f.description),
                  subtitle: Text(f.key),
                  value: f.enabled,
                  onChanged: (v) async {
                    if (f.key == 'maintenance_mode' && v) {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(tr('Activer la maintenance ?')),
                          content: Text(tr(
                              'Tous les utilisateurs (hors administrateurs) verront l’écran de maintenance.')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(tr('Annuler'))),
                            FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(tr('Activer'))),
                          ],
                        ),
                      );
                      if (ok != true) return;
                    }
                    try {
                      await ref.read(adminRepositoryProvider).setFlag(f.key, v);
                      ref.invalidate(adminFlagsProvider);
                      ref.invalidate(featureFlagsProvider);
                    } catch (e) {
                      if (context.mounted) {
                        showMessage(context, adminErrorMessage(e), error: true);
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Réglages : forfaits (éditeur dédié) puis tous les autres réglages.
class SettingsAdminScreen extends ConsumerWidget {
  const SettingsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(adminSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Réglages et forfaits'))),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Indisponible'),
            body: adminErrorMessage(e)),
        data: (list) {
          final plans = list.where((s) => s.key == 'pricing.plans').firstOrNull;
          final costs = {
            'analysis.credit_cost': tr('Analyse de match (forfait FREE)'),
            'lab.credit_cost': tr('Calcul du laboratoire (forfait FREE)'),
            'assistant.cost_per_action':
                tr('Action de l’assistant (tous forfaits)'),
          };
          final costSettings = [
            for (final k in costs.keys)
              if (list.where((s) => s.key == k).firstOrNull case final s?) s
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              if (plans != null) ...[
                SectionTitle(tr('Forfaits')),
                for (final (i, p) in (plans.value as List).indexed)
                  Card(
                    child: ListTile(
                      title: Text(asMap(p)['name'] as String? ?? ''),
                      subtitle: Text([
                        fcfa(asInt(asMap(p)['monthly_xof'])),
                        trf('{0} crédits / mois', [asMap(p)['ai_credits']]),
                        trf('{0} analyses / jour', [
                          asMap(asMap(p)['features'])[
                                  'match_analyses_per_day'] ??
                              '–'
                        ]),
                      ].join(' · ')),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () =>
                          _editPlan(context, ref, plans.value as List, i),
                    ),
                  ),
              ],
              if (costSettings.isNotEmpty) ...[
                SectionTitle(tr('Coûts en crédits')),
                for (final c in costSettings)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bolt),
                      title: Text(costs[c.key]!),
                      subtitle: Text(c.key),
                      trailing: Text(
                          trf('{0} crédit{1}', [
                            c.value,
                            (c.value is num && (c.value as num) > 1) ? 's' : ''
                          ]),
                          style: Theme.of(context).textTheme.titleSmall),
                      onTap: () => _editSetting(context, ref, c),
                    ),
                  ),
              ],
              SectionTitle(tr('Tous les réglages')),
              for (final s in list)
                Card(
                  child: ListTile(
                    title: Text(s.key),
                    subtitle: Text('${s.description}\n${_preview(s.value)}',
                        maxLines: 4, overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    trailing: Icon(
                        s.isPublic ? Icons.public : Icons.lock_outline,
                        size: 18),
                    onTap: () => _editSetting(context, ref, s),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _preview(Object? v) {
    final s = jsonEncode(v);
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  Future<void> _save(
      BuildContext context, WidgetRef ref, String key, Object? value) async {
    try {
      await ref.read(adminRepositoryProvider).setSetting(key, value);
      ref.invalidate(adminSettingsProvider);
      ref.invalidate(publicSettingsProvider);
      if (context.mounted) showMessage(context, tr('Réglage enregistré.'));
    } catch (e) {
      if (context.mounted) {
        showMessage(context, adminErrorMessage(e), error: true);
      }
    }
  }

  Future<void> _editSetting(
      BuildContext context, WidgetRef ref, AdminSetting s) async {
    final isNum = s.value is num;
    final isBool = s.value is bool;
    final ctrl = TextEditingController(
        text: isNum || s.value is String
            ? '${s.value}'
            : const JsonEncoder.withIndent('  ').convert(s.value));
    var boolValue = s.value == true;
    final result = await showDialog<Object?>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(s.key),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.description, style: Theme.of(c).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  if (isBool)
                    SwitchListTile(
                        value: boolValue,
                        onChanged: (v) => setState(() => boolValue = v),
                        title: Text(tr('Activé')))
                  else
                    TextField(
                      controller: ctrl,
                      maxLines: isNum ? 1 : 12,
                      minLines: 1,
                      keyboardType: isNum
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.multiline,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                    ),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: Text(tr('Annuler'))),
            FilledButton(
              onPressed: () {
                try {
                  if (isBool) {
                    Navigator.pop(c, boolValue);
                  } else if (isNum) {
                    Navigator.pop(
                        c, num.parse(ctrl.text.trim().replaceAll(',', '.')));
                  } else if (s.value is String) {
                    Navigator.pop(c, ctrl.text);
                  } else if (s.value == null) {
                    // Réglage encore vide : JSON si possible, sinon texte simple.
                    final t = ctrl.text.trim();
                    Object? v;
                    try {
                      v = jsonDecode(t);
                    } catch (_) {
                      v = t;
                    }
                    Navigator.pop(c, v);
                  } else {
                    Navigator.pop(c, jsonDecode(ctrl.text));
                  }
                } catch (_) {
                  showMessage(
                      c, tr('Valeur invalide (nombre ou JSON attendu).'),
                      error: true);
                }
              },
              child: Text(tr('Enregistrer')),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result != null && context.mounted) {
      await _save(context, ref, s.key, result);
    }
  }

  Future<void> _editPlan(
      BuildContext context, WidgetRef ref, List plans, int index) async {
    final plan = asMap(plans[index]);
    final features = asMap(plan['features']);
    final price = TextEditingController(text: '${plan['monthly_xof']}');
    final credits = TextEditingController(text: '${plan['ai_credits']}');
    final analyses = TextEditingController(
        text: '${features['match_analyses_per_day'] ?? ''}');
    var allCoupons = features['coupon_categories'] == 'all';
    var tipster = features['tipster_publish'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(trf('Forfait {0}', [plan['name']])),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: price,
                enabled: plan['code'] != 'FREE',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: tr('Prix mensuel (FCFA, multiple de 5)')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: credits,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration:
                    InputDecoration(labelText: tr('Crédits IA par mois')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: analyses,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: tr('Analyses de match par jour')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Coupons visibles à tout moment')),
                subtitle: Text(tr(
                    'Sinon : coupons et résultats visibles après les matchs')),
                value: allCoupons,
                onChanged: (v) => setState(() => allCoupons = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Profil Tipster et publication')),
                value: tipster,
                onChanged: (v) => setState(() => tipster = v),
              ),
              Text(
                  tr('Le studio et les autres avantages se règlent dans « Tous les réglages » (pricing.plans).'),
                  style: Theme.of(c).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(tr('Annuler'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('Enregistrer'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      final updated = [
        for (final (i, p) in plans.indexed)
          if (i != index)
            p
          else
            {
              ...plan,
              'monthly_xof': int.tryParse(price.text) ?? plan['monthly_xof'],
              'ai_credits': int.tryParse(credits.text) ?? plan['ai_credits'],
              'features': {
                ...features,
                if (int.tryParse(analyses.text) != null)
                  'match_analyses_per_day': int.parse(analyses.text),
                'coupon_categories': allCoupons ? 'all' : <String>[],
                'tipster_publish': tipster,
              },
            },
      ];
      if (context.mounted) await _save(context, ref, 'pricing.plans', updated);
    }
    price.dispose();
    credits.dispose();
    analyses.dispose();
  }
}

final _paymentStatus = {
  'succeeded': tr('Confirmés'),
  'pending': tr('En attente'),
  'failed': tr('Échoués'),
  'cancelled': tr('Abandonnés'),
  'refunded': tr('Remboursés')
};

class PaymentsAdminScreen extends ConsumerStatefulWidget {
  const PaymentsAdminScreen({super.key});

  @override
  ConsumerState<PaymentsAdminScreen> createState() =>
      _PaymentsAdminScreenState();
}

class _PaymentsAdminScreenState extends ConsumerState<PaymentsAdminScreen> {
  String? _status;

  Future<void> _actions(BuildContext context, Map<String, dynamic> p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (p['user_id'] != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(tr('Fiche de l’utilisateur')),
              onTap: () => Navigator.pop(c, 'user'),
            ),
          if (p['status'] == 'succeeded')
            ListTile(
              leading: const Icon(Icons.undo),
              title: Text(tr('Enregistrer un remboursement')),
              subtitle: Text(tr('Après remboursement chez l’agrégateur')),
              onTap: () => Navigator.pop(c, 'refund'),
            ),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (action == 'user') openAdminUser(context, p['user_id'] as String);
    if (action == 'refund') await recordRefund(context, ref, p);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminPaymentsProvider(_status));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Paiements'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          const PaymentProvidersCard(),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: Text(tr('Tous')),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null)),
            for (final e in _paymentStatus.entries)
              ChoiceChip(
                  label: Text(e.value),
                  selected: _status == e.key,
                  onSelected: (_) => setState(() => _status = e.key)),
          ]),
          const SizedBox(height: 8),
          Text(
              tr('Remboursement : rendre l’argent depuis le tableau de bord de l’agrégateur du paiement (LigdiCash ou CinetPay), puis toucher le paiement confirmé ici pour l’enregistrer (les droits accordés sont retirés).'),
              style: Theme.of(context).textTheme.bodySmall),
          ...list.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(adminErrorMessage(e))],
            data: (rows) => rows.isEmpty
                ? [
                    Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(tr('Aucun paiement.')))
                  ]
                : [
                    for (final p in rows)
                      Card(
                        child: ListTile(
                          title: Text(
                              '${fcfa(asInt(p['amount_xof']))} · ${p['kind'] == 'subscription' ? trf('Forfait {0} ({1})', [
                                      p['plan'],
                                      p['period']
                                    ]) : trf('{0} crédits', [p['credits']])}'),
                          subtitle: Text([
                            '${p['email'] ?? ''}',
                            '${_when(p['created_at'] as String?)} · ${p['transaction_id']}${p['provider'] == null ? '' : ' · ${p['provider'] == 'ligdicash' ? 'LigdiCash' : 'CinetPay'}'}',
                            if (p['promo_code'] != null)
                              trf('Code {0} (−{1})', [
                                p['promo_code'],
                                fcfa(asInt(p['discount_xof']))
                              ]),
                            if (p['refund_reason'] != null)
                              trf('Remboursé le {0} : {1}', [
                                _when(p['refunded_at'] as String?),
                                p['refund_reason']
                              ]),
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: Text(
                              _paymentStatus[p['status']] ?? '${p['status']}'),
                          onTap: () => _actions(context, p),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class AuditAdminScreen extends ConsumerStatefulWidget {
  const AuditAdminScreen({super.key});

  @override
  ConsumerState<AuditAdminScreen> createState() => _AuditAdminScreenState();
}

class _AuditAdminScreenState extends ConsumerState<AuditAdminScreen> {
  String? _filter;

  static final _filters = {
    'users.': tr('Utilisateurs'),
    'settings.': tr('Réglages'),
    'flag': tr('Modules'),
    'moderation.': tr('Modération'),
    'payment.': tr('Paiements'),
    'coupon': tr('Coupons'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(adminAuditProvider(_filter));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Journal d’audit'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(
                label: Text(tr('Tout')),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null)),
            for (final e in _filters.entries)
              ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) => setState(() => _filter = e.key)),
          ]),
          const SizedBox(height: 8),
          ...list.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(adminErrorMessage(e))],
            data: (rows) => rows.isEmpty
                ? [
                    Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(tr('Aucune entrée.')))
                  ]
                : [
                    for (final a in rows)
                      Card(
                        child: ExpansionTile(
                          title: Text('${a['action']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${a['actor']} · ${_when(a['created_at'] as String?)}'
                              '${a['target_type'] == null ? '' : ' · ${a['target_type']} ${a['target_id'] ?? ''}'}'),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                                const JsonEncoder.withIndent('  ')
                                    .convert(a['details']),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}
