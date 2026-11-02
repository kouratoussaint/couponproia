import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/ai_providers_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

final _periods = {
  'today': tr('Aujourd’hui'),
  'days_7': tr('7 j'),
  'days_30': tr('30 j')
};

const _initials = {'gemini': 'G', 'groq': 'Q', 'anthropic': 'C'};

const _tints = {
  'gemini': Color(0xFF1A73E8),
  'groq': Color(0xFFF55036),
  'anthropic': Color(0xFFC96442),
};

String _int(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

String _seconds(int? ms) => ms == null
    ? '–'
    : trf('{0} s',
        [(ms / 1000).toStringAsFixed(1).replaceAll('.', decimalSeparator)]);

String _usd(double? v) => v == null
    ? '–'
    : '${v.toStringAsFixed(2).replaceAll('.', decimalSeparator)} \$';

/// Console → Fournisseurs d'IA (super administrateur) : rôle de chaque IA dans l'ordre
/// d'appel, modèle, consommation, quota et test de connexion.
class AiProvidersScreen extends ConsumerStatefulWidget {
  const AiProvidersScreen({super.key});

  @override
  ConsumerState<AiProvidersScreen> createState() => _AiProvidersScreenState();
}

class _AiProvidersScreenState extends ConsumerState<AiProvidersScreen> {
  String _period = 'days_7';
  Map<String, AiRole>? _roles;
  Map<String, String> _models = {};
  bool _saving = false;
  final Set<String> _testing = {};

  void _reset(List<AiProviderInfo> list) {
    // Une IA sans clé est toujours désactivée (même si un ancien réglage la plaçait en secours).
    _roles = {
      for (final p in list) p.name: p.configured ? p.role : AiRole.disabled
    };
    _models = {
      for (final p in list)
        if (p.model != null) p.name: p.model!
    };
  }

  bool _dirty(List<AiProviderInfo> list) =>
      list.any((p) => _roles?[p.name] != p.role || _models[p.name] != p.model);

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('ai.providers')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Fournisseurs d’IA'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Écran réservé au super administrateur')),
      );
    }
    final async = ref.watch(aiProvidersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Fournisseurs d’IA'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Indisponible'),
            body: e is AiProvidersException ? e.message : userMessageFor(e)),
        data: (list) {
          if (_roles == null) _reset(list);
          final order = orderOf(_roles!);
          final labels = {for (final p in list) p.name: p.label};
          final dirty = _dirty(list);
          return RefreshIndicator(
            onRefresh: () async {
              _roles = null;
              ref.invalidate(aiProvidersProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                SegmentedButton<String>(
                  segments: [
                    for (final e in _periods.entries)
                      ButtonSegment(value: e.key, label: Text(e.value)),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.first),
                ),
                const SizedBox(height: 12),
                _OrderBanner(
                  text: order.primary == null
                      ? tr('Aucune IA principale : choisissez-en une.')
                      : trf('Ordre d’appel : {0}', [
                          [order.primary!, ...order.fallbacks]
                              .map((n) => labels[n] ?? n)
                              .join(' → ')
                        ]),
                  warning: order.primary == null,
                ),
                const SizedBox(height: 4),
                for (final p in list)
                  _ProviderCard(
                    info: p,
                    period: _period,
                    role: _roles![p.name] ?? AiRole.disabled,
                    model: _models[p.name],
                    testing: _testing.contains(p.name),
                    onRole: (r) =>
                        setState(() => _roles = assignRole(_roles!, p.name, r)),
                    onModel: () => _pickModel(p),
                    onTest: () => _test(p),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: !dirty || _saving || order.primary == null
                      ? null
                      : () => _save(list, labels),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(tr('Enregistrer les changements')),
                ),
                if (dirty)
                  TextButton(
                    onPressed: () => setState(() => _reset(list)),
                    child: Text(tr('Annuler les changements')),
                  ),
                const SizedBox(height: 8),
                Text(
                  tr('Une seule principale à la fois ; une IA sans clé ne peut pas être choisie. Si la principale échoue ou atteint sa limite, la suivante prend le relais pour la même analyse. Chaque changement est inscrit au journal d’audit. « Tester » envoie une courte requête sans données d’utilisateur. Les clés restent sur le serveur : l’application ne les voit jamais.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickModel(AiProviderInfo p) async {
    final repo = ref.read(aiProvidersRepositoryProvider);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _ModelSheet(
          provider: p,
          current: _models[p.name],
          load: () => repo.models(p.name)),
    );
    if (chosen != null && chosen.trim().isNotEmpty) {
      setState(() => _models[p.name] = chosen.trim());
    }
  }

  Future<void> _test(AiProviderInfo p) async {
    setState(() => _testing.add(p.name));
    try {
      final r = await ref
          .read(aiProvidersRepositoryProvider)
          .test(p.name, _models[p.name]);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(r.ok ? Icons.check_circle_outline : Icons.error_outline),
          title: Text(r.ok
              ? trf('{0} répond', [p.label])
              : trf('{0} ne répond pas', [p.label])),
          content: Text([
            trf('Modèle : {0}', [r.model]),
            trf('Temps de réponse : {0}', [_seconds(r.latencyMs)]),
            if (r.error != null) trf('Erreur : {0}', [r.error]),
            if (r.quota?.requestsRemaining != null)
              trf('Requêtes restantes : {0}{1}', [
                _int(r.quota!.requestsRemaining!),
                r.quota!.requestsLimit == null
                    ? ''
                    : trf(' sur {0}', [_int(r.quota!.requestsLimit!)])
              ]),
            if (r.quota?.tokensRemaining != null)
              trf('Jetons restants : {0}{1}', [
                _int(r.quota!.tokensRemaining!),
                r.quota!.tokensLimit == null
                    ? ''
                    : trf(' sur {0}', [_int(r.quota!.tokensLimit!)])
              ]),
          ].join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: Text(tr('Fermer')))
          ],
        ),
      );
      ref.invalidate(aiProvidersProvider);
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is AiProvidersException ? e.message : userMessageFor(e));
      }
    } finally {
      if (mounted) setState(() => _testing.remove(p.name));
    }
  }

  Future<void> _save(
      List<AiProviderInfo> list, Map<String, String> labels) async {
    final order = orderOf(_roles!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Appliquer ce choix ?')),
        content: Text(
          trf(
              'Principale : {0} ({1})\n{2}\n\nLes prochaines analyses utiliseront cet ordre.',
              [
                labels[order.primary],
                _models[order.primary] ?? tr('modèle non choisi'),
                order.fallbacks.isEmpty
                    ? tr('Aucune IA de secours.')
                    : order.fallbacks
                        .asMap()
                        .entries
                        .map((e) => trf('Secours {0} : {1} ({2})', [
                              e.key + 1,
                              labels[e.value],
                              _models[e.value] ?? '–'
                            ]))
                        .join('\n')
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Appliquer'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(aiProvidersRepositoryProvider).save(
            primary: order.primary!,
            fallbacks: order.fallbacks,
            models: _models,
          );
      _roles = null;
      ref.invalidate(aiProvidersProvider);
      if (mounted) showMessage(context, tr('Fournisseurs d’IA mis à jour.'));
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is AiProvidersException ? e.message : userMessageFor(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _OrderBanner extends StatelessWidget {
  const _OrderBanner({required this.text, required this.warning});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: warning ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: warning
                  ? scheme.onErrorContainer
                  : scheme.onPrimaryContainer)),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.info,
    required this.period,
    required this.role,
    required this.model,
    required this.testing,
    required this.onRole,
    required this.onModel,
    required this.onTest,
  });

  final AiProviderInfo info;
  final String period;
  final AiRole role;
  final String? model;
  final bool testing;
  final ValueChanged<AiRole> onRole;
  final VoidCallback onModel;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final u = info.periods[period] ?? const AiPeriodUsage();
    final today = info.periods['today'] ?? const AiPeriodUsage();
    final active = role != AiRole.disabled;
    final last = info.lastCallAt;
    return Opacity(
      opacity: info.configured ? 1 : 0.65,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: role == AiRole.primary
                  ? scheme.primary
                  : scheme.outlineVariant,
              width: role == AiRole.primary ? 1.5 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tints[info.name] ?? scheme.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                        _initials[info.name] ?? info.label.substring(0, 1),
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info.label, style: theme.textTheme.titleMedium),
                        Text(model ?? tr('Modèle non choisi'),
                            style: muted, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: role == AiRole.primary
                          ? scheme.primary
                          : active
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(role.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: role == AiRole.primary
                                ? scheme.onPrimary
                                : active
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                !info.configured
                    ? trf(
                        'Clé absente : ajoutez {0} dans les secrets du dépôt.',
                        [info.secret])
                    : last == null
                        ? tr('Clé configurée · aucun appel pour l’instant')
                        : trf(
                            'Clé configurée · dernier appel le {0} à {1}{2}', [
                            shortDate(last),
                            timeLabel(last),
                            info.lastCallStatus == 'success'
                                ? ''
                                : ' (${info.lastCallStatus == 'invalid' ? tr('réponse rejetée') : 'erreur'})'
                          ]),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: info.configured ? scheme.primary : scheme.error),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Stat(value: _int(u.calls), label: tr('appels')),
                  _Stat(value: _int(u.rejected), label: tr('rejetés')),
                  _Stat(value: _seconds(u.avgLatencyMs), label: tr('moyenne')),
                  _Stat(value: _usd(u.costUsd), label: tr('coût')),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                trf(
                    'Erreurs : {0} · limites atteintes : {1} · jetons : {2} envoyés, {3} reçus',
                    [
                      u.errors,
                      u.rateLimited,
                      _int(u.inputTokens),
                      _int(u.outputTokens)
                    ]),
                style: muted,
              ),
              const SizedBox(height: 10),
              _QuotaBlock(info: info, today: today),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PopupMenuButton<AiRole>(
                      enabled: info.configured,
                      initialValue: role,
                      onSelected: onRole,
                      itemBuilder: (_) => [
                        for (final r in AiRole.values)
                          PopupMenuItem(value: r, child: Text(r.label)),
                      ],
                      child: _OutlineBox(
                          text: trf('Rôle : {0}', [role.label]),
                          enabled: info.configured),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: tr('Changer de modèle'),
                    onPressed: info.configured ? onModel : null,
                    icon: const Icon(Icons.tune),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: info.configured && !testing ? onTest : null,
                    child: testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('Tester')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineBox extends StatelessWidget {
  const _OutlineBox({required this.text, required this.enabled});

  final String text;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: enabled ? null : scheme.onSurfaceVariant))),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800))),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Quota : annoncé par le fournisseur s'il en envoie, sinon compteur du jour face aux
/// limites de référence de l'offre gratuite.
class _QuotaBlock extends StatelessWidget {
  const _QuotaBlock({required this.info, required this.today});

  final AiProviderInfo info;
  final AiPeriodUsage today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final q = info.lastQuota;
    final rows = <Widget>[];
    void bar(String label, int used, int limit, String text) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(label, style: muted)),
              Text(text, style: theme.textTheme.labelLarge),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: limit <= 0 ? 0 : (used / limit).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ));
    }

    if (q != null &&
        (q.requestsRemaining != null || q.tokensRemaining != null)) {
      if (q.requestsLimit != null && q.requestsRemaining != null) {
        bar(
            tr('Requêtes restantes'),
            q.requestsLimit! - q.requestsRemaining!,
            q.requestsLimit!,
            '${_int(q.requestsRemaining!)} / ${_int(q.requestsLimit!)}');
      }
      if (q.tokensLimit != null && q.tokensRemaining != null) {
        bar(
            tr('Jetons restants'),
            q.tokensLimit! - q.tokensRemaining!,
            q.tokensLimit!,
            '${_int(q.tokensRemaining!)} / ${_int(q.tokensLimit!)}');
      }
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          trf('Annoncé par {0}{1}{2}', [
            info.label,
            q.at == null
                ? ''
                : trf(' le {0} à {1}', [shortDate(q.at!), timeLabel(q.at!)]),
            q.requestsReset == null
                ? ''
                : trf(
                    ' · remise à zéro des requêtes dans {0}', [q.requestsReset])
          ]),
          style: muted,
        ),
      ));
    } else if (info.referenceLimits.isNotEmpty) {
      final perDay = info.referenceLimits['requests_per_day'];
      final tokensDay = info.referenceLimits['tokens_per_day'];
      if (perDay != null) {
        bar(tr('Requêtes du jour (offre gratuite)'), today.calls, perDay,
            '${_int(today.calls)} / ${_int(perDay)}');
      }
      if (tokensDay != null) {
        final used = today.inputTokens + today.outputTokens;
        bar(tr('Jetons du jour'), used, tokensDay,
            '${_int(used)} / ${_int(tokensDay)}');
      }
      final perMinute = info.referenceLimits['requests_per_minute'];
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          trf(
              'Limites de référence de l’offre gratuite{0}. Le quota exact s’affichera après le premier appel.',
              [
                perMinute == null
                    ? ''
                    : trf(' (dont {0} requêtes par minute)', [perMinute])
              ]),
          style: muted,
        ),
      ));
    } else {
      rows.add(Text(
        trf('{0} n’annonce pas son quota : {1} appel{2} aujourd’hui.',
            [info.label, _int(today.calls), today.calls > 1 ? 's' : '']),
        style: muted,
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _ModelSheet extends StatefulWidget {
  const _ModelSheet(
      {required this.provider, required this.current, required this.load});

  final AiProviderInfo provider;
  final String? current;
  final Future<List<String>> Function() load;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  late final Future<List<String>> _future = widget.load();
  late final _custom = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(trf('Modèle {0}', [widget.provider.label]),
                  style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _custom,
                decoration: InputDecoration(
                  labelText: tr('Nom du modèle'),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () => Navigator.pop(context, _custom.text),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _future,
                builder: (c, s) {
                  if (s.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (s.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          s.error is AiProvidersException
                              ? '${s.error}'
                              : tr(
                                  'Liste des modèles indisponible : saisissez le nom.'),
                          style: theme.textTheme.bodyMedium),
                    );
                  }
                  final models = s.data ?? const [];
                  return ListView(
                    children: [
                      for (final m in models)
                        ListTile(
                          dense: true,
                          title: Text(m),
                          trailing: m == widget.current
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, m),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
