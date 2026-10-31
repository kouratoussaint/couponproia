import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/form_widgets.dart';
import '../data/admin_repository.dart';

/// Agrégateur de paiement tel que vu par le serveur (jamais les clés).
class PaymentProviderInfo {
  const PaymentProviderInfo(
      {required this.name, required this.configured, required this.secrets});

  final String name;
  final bool configured;
  final List<String> secrets;

  String get label => name == 'ligdicash' ? 'LigdiCash' : 'CinetPay';
}

class PaymentProvidersState {
  const PaymentProvidersState({required this.providers, required this.order});

  final List<PaymentProviderInfo> providers;

  /// Ordre enregistré (réglage payments.providers), y compris ceux sans clé.
  final List<String> order;
}

final paymentProvidersProvider =
    FutureProvider.autoDispose<PaymentProvidersState>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final res = await client.functions
      .invoke('payments', body: const {'action': 'providers'});
  final data = asMap(res.data);
  final providers = [
    for (final p in asList(data['providers']))
      PaymentProviderInfo(
        name: p['name'] as String,
        configured: p['configured'] == true,
        secrets: [for (final s in (p['secrets'] as List? ?? const [])) '$s'],
      ),
  ];
  final setting = data['setting'];
  final order = setting is List && setting.isNotEmpty
      ? [for (final s in setting) '$s']
      : const ['ligdicash', 'cinetpay'];
  return PaymentProvidersState(providers: providers, order: order);
});

/// Console → Paiements : agrégateurs actifs et ordre de priorité (le premier configuré est
/// utilisé ; si sa facture est refusée, le suivant prend le relais).
class PaymentProvidersCard extends ConsumerStatefulWidget {
  const PaymentProvidersCard({super.key});

  @override
  ConsumerState<PaymentProvidersCard> createState() =>
      _PaymentProvidersCardState();
}

class _PaymentProvidersCardState extends ConsumerState<PaymentProvidersCard> {
  List<String>? _order;
  Set<String>? _enabled;
  bool _saving = false;
  bool _testing = false;

  /// Crée une facture de test (100 FCFA, jamais présentée) pour vérifier les clés.
  Future<void> _test(String name, String label) async {
    setState(() => _testing = true);
    try {
      final res = await ref.read(supabaseClientProvider).functions.invoke(
          'payments',
          body: {'action': 'provider_test', 'provider': name});
      final d = asMap(res.data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(d['ok'] == true
              ? Icons.check_circle_outline
              : Icons.error_outline),
          title: Text(d['ok'] == true
              ? '$label répond : clés valides'
              : '$label refuse la facture de test'),
          content: Text(d['ok'] == true
              ? 'Facture de test de 100 FCFA créée en ${((asInt(d['latency_ms'])) / 1000).toStringAsFixed(1).replaceAll('.', ',')} s, '
                  'jamais présentée à un client. Pour un essai complet, achetez le plus petit pack depuis l’application.'
              : 'Réponse : ${d['message'] ?? 'inconnue'}. Vérifiez les clés et l’activation du projet chez $label.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Fermer'))
          ],
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Test impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(paymentProvidersProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(e is FunctionException
              ? 'Agrégateurs indisponibles (code ${e.status}).'
              : 'Agrégateurs indisponibles pour le moment.'),
          data: (s) {
            final all = [
              ...s.order,
              for (final p in s.providers)
                if (!s.order.contains(p.name)) p.name
            ];
            _order ??= all;
            _enabled ??= s.order.toSet();
            final byName = {for (final p in s.providers) p.name: p};
            final active = [
              for (final n in _order!)
                if (_enabled!.contains(n) && (byName[n]?.configured ?? false))
                  byName[n]!.label
            ];
            final dirty = _order!.where(_enabled!.contains).join(',') !=
                s.order.join(',');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Agrégateurs de paiement',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  active.isEmpty
                      ? 'Aucun agrégateur actif avec ses clés : les achats sont indisponibles.'
                      : 'Utilisé pour les achats : ${active.first}'
                          '${active.length > 1 ? ' (relais : ${active.skip(1).join(', ')})' : ''}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: active.isEmpty ? scheme.error : scheme.primary),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _order!.length; i++)
                  _row(context, i, byName[_order![i]]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Les clés se règlent dans les secrets du dépôt, jamais dans l’application.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          !dirty || _saving || _enabled!.isEmpty ? null : _save,
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i, PaymentProviderInfo? p) {
    final theme = Theme.of(context);
    final name = _order![i];
    final label = p?.label ?? name;
    final on = _enabled!.contains(name);
    final rank = _order!.where(_enabled!.contains).toList().indexOf(name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: on
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            child: Text(on ? '${rank + 1}' : '–',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: on
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                Text(
                  p?.configured ?? false
                      ? 'Clés configurées'
                      : 'Clés absentes : ${p?.secrets.join(', ') ?? ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: p?.configured ?? false
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error),
                ),
              ],
            ),
          ),
          if (p?.configured ?? false)
            TextButton(
              onPressed: _testing ? null : () => _test(name, label),
              child: const Text('Tester'),
            ),
          IconButton(
            tooltip: 'Monter',
            visualDensity: VisualDensity.compact,
            onPressed: i == 0
                ? null
                : () => setState(() {
                      final o = [..._order!];
                      final x = o.removeAt(i);
                      o.insert(i - 1, x);
                      _order = o;
                    }),
            icon: const Icon(Icons.arrow_upward),
          ),
          Switch(
            value: on,
            onChanged: (v) => setState(() {
              final e = {..._enabled!};
              v ? e.add(name) : e.remove(name);
              _enabled = e;
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final value = _order!.where(_enabled!.contains).toList();
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setSetting('payments.providers', value);
      ref.invalidate(paymentProvidersProvider);
      _order = null;
      _enabled = null;
      if (mounted) showMessage(context, 'Agrégateurs enregistrés.');
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
