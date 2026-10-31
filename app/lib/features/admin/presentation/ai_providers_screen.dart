import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/ai_providers_repository.dart';

const _periods = {'today': 'Aujourd’hui', 'days_7': '7 j', 'days_30': '30 j'};

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
    : '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

String _usd(double? v) =>
    v == null ? '–' : '${v.toStringAsFixed(2).replaceAll('.', ',')} \$';

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
    _roles = {for (final p in list) p.name: p.role};
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
        appBar: AppBar(title: const Text('Fournisseurs d’IA')),
        body: const InfoMessage(
            icon: Icons.lock_outline,
            title: 'Écran réservé au super administrateur'),
      );
    }
    final async = ref.watch(aiProvidersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fournisseurs d’IA')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
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
                      ? 'Aucune IA principale : choisissez-en une.'
                      : 'Ordre d’appel : ${[
                          order.primary!,
                          ...order.fallbacks
                        ].map((n) => labels[n] ?? n).join(' → ')}',
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
                  label: const Text('Enregistrer les changements'),
                ),
                if (dirty)
                  TextButton(
                    onPressed: () => setState(() => _reset(list)),
                    child: const Text('Annuler les changements'),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Une seule principale à la fois ; une IA sans clé ne peut pas être choisie. '
                  'Si la principale échoue ou atteint sa limite, la suivante prend le relais pour la même analyse. '
                  'Chaque changement est inscrit au journal d’audit. « Tester » envoie une courte requête sans données d’utilisateur. '
                  'Les clés restent sur le serveur : l’application ne les voit jamais.',
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
          title: Text(r.ok ? '${p.label} répond' : '${p.label} ne répond pas'),
          content: Text([
            'Modèle : ${r.model}',
            'Temps de réponse : ${_seconds(r.latencyMs)}',
            if (r.error != null) 'Erreur : ${r.error}',
            if (r.quota?.requestsRemaining != null)
              'Requêtes restantes : ${_int(r.quota!.requestsRemaining!)}'
                  '${r.quota!.requestsLimit == null ? '' : ' sur ${_int(r.quota!.requestsLimit!)}'}',
            if (r.quota?.tokensRemaining != null)
              'Jetons restants : ${_int(r.quota!.tokensRemaining!)}'
                  '${r.quota!.tokensLimit == null ? '' : ' sur ${_int(r.quota!.tokensLimit!)}'}',
          ].join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Fermer'))
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
        title: const Text('Appliquer ce choix ?'),
        content: Text(
          'Principale : ${labels[order.primary]} (${_models[order.primary] ?? 'modèle non choisi'})\n'
          '${order.fallbacks.isEmpty ? 'Aucune IA de secours.' : order.fallbacks.asMap().entries.map((e) => 'Secours ${e.key + 1} : ${labels[e.value]} (${_models[e.value] ?? '–'})').join('\n')}\n\n'
          'Les prochaines analyses utiliseront cet ordre.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Appliquer')),
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
      if (mounted) showMessage(context, 'Fournisseurs d’IA mis à jour.');
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
                        Text(model ?? 'Modèle non choisi',
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
                    ? 'Clé absente : ajoutez ${info.secret} dans les secrets du dépôt.'
                    : last == null
                        ? 'Clé configurée · aucun appel pour l’instant'
                        : 'Clé configurée · dernier appel le ${shortDate(last)} à ${timeLabel(last)}'
                            '${info.lastCallStatus == 'success' ? '' : ' (${info.lastCallStatus == 'invalid' ? 'réponse rejetée' : 'erreur'})'}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: info.configured ? scheme.primary : scheme.error),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Stat(value: _int(u.calls), label: 'appels'),
                  _Stat(value: _int(u.rejected), label: 'rejetés'),
                  _Stat(value: _seconds(u.avgLatencyMs), label: 'moyenne'),
                  _Stat(value: _usd(u.costUsd), label: 'coût'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Erreurs : ${u.errors} · limites atteintes : ${u.rateLimited} · '
                'jetons : ${_int(u.inputTokens)} envoyés, ${_int(u.outputTokens)} reçus',
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
                          text: 'Rôle : ${role.label}',
                          enabled: info.configured),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Changer de modèle',
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
                        : const Text('Tester'),
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
            'Requêtes restantes',
            q.requestsLimit! - q.requestsRemaining!,
            q.requestsLimit!,
            '${_int(q.requestsRemaining!)} / ${_int(q.requestsLimit!)}');
      }
      if (q.tokensLimit != null && q.tokensRemaining != null) {
        bar(
            'Jetons restants',
            q.tokensLimit! - q.tokensRemaining!,
            q.tokensLimit!,
            '${_int(q.tokensRemaining!)} / ${_int(q.tokensLimit!)}');
      }
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Annoncé par ${info.label}'
          '${q.at == null ? '' : ' le ${shortDate(q.at!)} à ${timeLabel(q.at!)}'}'
          '${q.requestsReset == null ? '' : ' · remise à zéro des requêtes dans ${q.requestsReset}'}',
          style: muted,
        ),
      ));
    } else if (info.referenceLimits.isNotEmpty) {
      final perDay = info.referenceLimits['requests_per_day'];
      final tokensDay = info.referenceLimits['tokens_per_day'];
      if (perDay != null) {
        bar('Requêtes du jour (offre gratuite)', today.calls, perDay,
            '${_int(today.calls)} / ${_int(perDay)}');
      }
      if (tokensDay != null) {
        final used = today.inputTokens + today.outputTokens;
        bar('Jetons du jour', used, tokensDay,
            '${_int(used)} / ${_int(tokensDay)}');
      }
      final perMinute = info.referenceLimits['requests_per_minute'];
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Limites de référence de l’offre gratuite'
          '${perMinute == null ? '' : ' (dont $perMinute requêtes par minute)'}. '
          'Le quota exact s’affichera après le premier appel.',
          style: muted,
        ),
      ));
    } else {
      rows.add(Text(
        '${info.label} n’annonce pas son quota : ${_int(today.calls)} appel${today.calls > 1 ? 's' : ''} aujourd’hui.',
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
              child: Text('Modèle ${widget.provider.label}',
                  style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _custom,
                decoration: InputDecoration(
                  labelText: 'Nom du modèle',
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
                              : 'Liste des modèles indisponible : saisissez le nom.',
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
