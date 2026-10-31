import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../analysis/data/analysis_repository.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/coupon_models.dart';
import '../data/coupon_repository.dart';
import 'coupon_widgets.dart';

const _triggerLabels = {
  'schedule': 'Programmée',
  'continuous': 'Continue',
  'manual': 'Manuelle'
};
const _runStatusLabels = {
  'running': 'En cours',
  'success': 'Réussie',
  'partial': 'Partielle',
  'refused': 'Refus motivé',
  'failed': 'Échec technique',
};

/// Administration minimale des générations : profils, génération à la demande,
/// validation humaine, journal des générations avec leurs motifs de refus.
class GenerationsAdminScreen extends ConsumerStatefulWidget {
  const GenerationsAdminScreen({super.key});

  @override
  ConsumerState<GenerationsAdminScreen> createState() =>
      _GenerationsAdminScreenState();
}

class _GenerationsAdminScreenState
    extends ConsumerState<GenerationsAdminScreen> {
  int? _generating;

  void _refresh() {
    ref.invalidate(couponProfilesProvider);
    ref.invalidate(generationRunsProvider);
    ref.invalidate(unpublishedCouponsProvider);
    invalidateCouponLists(ref);
  }

  Future<void> _generate(CouponProfile p) async {
    setState(() => _generating = p.id);
    try {
      final res = await ref.read(couponRepositoryProvider).generateNow(p.id);
      final run = res['run'] as Map?;
      final reasons = (run?['reasons'] as List?)?.join('\n') ?? '';
      if (mounted) {
        showMessage(
          context,
          run == null
              ? 'Génération non lancée.'
              : '${_runStatusLabels[run['status']] ?? run['status']} : ${run['coupons']} coupon(s)'
                  '${reasons.isEmpty ? '' : '\n$reasons'}',
          error: run?['status'] == 'failed',
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is AnalysisException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _generating = null);
    }
  }

  Future<void> _update(CouponProfile p, Map<String, dynamic> patch) async {
    try {
      await ref.read(couponRepositoryProvider).updateProfile(p.id, patch);
      ref.invalidate(couponProfilesProvider);
      if (mounted) showMessage(context, 'Profil « ${p.name} » mis à jour.');
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    }
  }

  Future<void> _review(Coupon c, bool approve) async {
    try {
      await ref.read(couponRepositoryProvider).review(c.id, approve: approve);
      _refresh();
      if (mounted) {
        showMessage(
            context,
            approve
                ? 'Coupon validé : il sera publié à son heure.'
                : 'Coupon rejeté.');
      }
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!permissions.contains('generation.manage')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Générations de coupons')),
        body: const InfoMessage(
            icon: Icons.lock_outline,
            title: 'Accès réservé aux administrateurs'),
      );
    }
    final profiles = ref.watch(couponProfilesProvider);
    final pending = ref.watch(unpublishedCouponsProvider);
    final runs = ref.watch(generationRunsProvider);
    final flags =
        ref.watch(featureFlagsProvider).valueOrNull ?? const <String, bool>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Générations de coupons'),
        actions: [
          IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Text(
              'Le moteur se réveille toutes les 15 minutes : il génère les créneaux échus (heure de '
              'Ouagadougou), puis publie les coupons prêts après un dernier contrôle. '
              'Génération programmée : ${flags['auto_generation_scheduled'] == true ? 'active' : 'coupée'} · '
              'continue : ${flags['auto_generation_continuous'] == true ? 'active' : 'coupée'}.',
              style: theme.textTheme.bodySmall,
            ),
            const SectionTitle('Profils de génération'),
            profiles.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) => Column(
                children: [
                  for (final p in list)
                    _ProfileCard(
                      profile: p,
                      generating: _generating == p.id,
                      onGenerate:
                          _generating == null ? () => _generate(p) : null,
                      onToggle: (v) => _update(p, {'is_active': v}),
                      onEdit: () async {
                        final patch =
                            await showModalBottomSheet<Map<String, dynamic>>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => _ProfileEditor(profile: p),
                        );
                        if (patch != null && patch.isNotEmpty) {
                          await _update(p, patch);
                        }
                      },
                    ),
                ],
              ),
            ),
            const SectionTitle('À valider et programmés'),
            pending.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) => list.isEmpty
                  ? Text('Aucun coupon en attente.',
                      style: theme.textTheme.bodyMedium)
                  : Column(
                      children: [
                        for (final c in list)
                          CouponCard(
                            coupon: c,
                            onTap: () =>
                                context.push(AppRoutes.couponDetailFor(c.id)),
                            trailing: c.status == 'pending_review'
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Rejeter',
                                        icon: Icon(Icons.close,
                                            color: theme.colorScheme.error),
                                        onPressed: () => _review(c, false),
                                      ),
                                      IconButton.filledTonal(
                                        tooltip: 'Valider',
                                        icon: const Icon(Icons.check),
                                        onPressed: () => _review(c, true),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Publication ${couponDateLabel(c.publishAt, DateTime.now())}',
                                    style: theme.textTheme.labelSmall),
                          ),
                      ],
                    ),
            ),
            const SectionTitle('Journal des générations'),
            runs.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(userMessageFor(e)),
              data: (list) => list.isEmpty
                  ? Text('Aucune génération pour l’instant.',
                      style: theme.textTheme.bodyMedium)
                  : Card(
                      child: Column(
                          children: [for (final r in list) _RunTile(run: r)])),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.generating,
    required this.onGenerate,
    required this.onToggle,
    required this.onEdit,
  });

  final CouponProfile profile;
  final bool generating;
  final VoidCallback? onGenerate;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final c = p.criteria;
    String n(String k, [int digits = 2]) =>
        c[k] is num ? decimal((c[k] as num).toDouble(), digits) : '?';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(p.name, style: theme.textTheme.titleMedium)),
                Switch(value: p.isActive, onChanged: onToggle),
              ],
            ),
            Text(
              [
                p.mode == 'scheduled'
                    ? 'Programmé ${p.generateTimes.join(', ')} (+${p.publishDelayMinutes} min)'
                    : 'Continu',
                p.publishMode == 'auto'
                    ? 'publication automatique'
                    : 'validation humaine',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${c['min_selections'] ?? '?'} à ${c['max_selections'] ?? '?'} sélections · cote ${n('min_total_odd')} à ${n('max_total_odd')} · '
              'modèle ≥ ${c['min_model_probability'] is num ? pct((c['min_model_probability'] as num).toDouble()) : '?'} · '
              'marchés ${(c['markets'] as List?)?.join(', ') ?? '?'} · fenêtre ${c['window_hours'] ?? '?'} h',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.tune),
                    label: const Text('Réglages')),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onGenerate,
                  icon: generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Générer maintenant'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final GenerationRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = run;
    final color = switch (r.status) {
      'success' => theme.colorScheme.primary,
      'partial' => BrandColors.orange,
      'failed' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return ListTile(
      isThreeLine: r.reasons.isNotEmpty,
      title: Text(
          '${r.profileName} · ${_triggerLabels[r.trigger] ?? r.trigger}${r.slotKey == null ? '' : ' ${r.slotKey}'}'),
      subtitle: Text(
        [
          '${shortDate(r.startedAt)} ${timeLabel(r.startedAt)} · ${r.candidates} candidat(s) · ${r.couponsCreated} coupon(s)',
          ...r.reasons,
        ].join('\n'),
      ),
      trailing: Text(_runStatusLabels[r.status] ?? r.status,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

/// Réglages principaux d'un profil (les autres critères gardent leur valeur).
class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.profile});

  final CouponProfile profile;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _times =
      TextEditingController(text: widget.profile.generateTimes.join(', '));
  late final _delay =
      TextEditingController(text: '${widget.profile.publishDelayMinutes}');
  late final _minSel = TextEditingController(
      text: '${widget.profile.criteria['min_selections'] ?? ''}');
  late final _maxSel = TextEditingController(
      text: '${widget.profile.criteria['max_selections'] ?? ''}');
  late final _minOdd = TextEditingController(
      text: '${widget.profile.criteria['min_total_odd'] ?? ''}');
  late final _maxOdd = TextEditingController(
      text: '${widget.profile.criteria['max_total_odd'] ?? ''}');
  late final _minProb = TextEditingController(
    text: widget.profile.numberOf('min_model_probability') == null
        ? ''
        : '${(widget.profile.numberOf('min_model_probability')! * 100).round()}',
  );
  late final _window = TextEditingController(
      text: '${widget.profile.criteria['window_hours'] ?? ''}');
  late bool _review = widget.profile.publishMode == 'review';
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _times,
      _delay,
      _minSel,
      _maxSel,
      _minOdd,
      _maxOdd,
      _minProb,
      _window
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _num(TextEditingController c) =>
      num.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final times = _times.text
        .split(RegExp(r'[,; ]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final timeOk = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (widget.profile.mode == 'scheduled' &&
        (times.isEmpty || times.any((t) => !timeOk.hasMatch(t)))) {
      setState(() => _error =
          'Heures au format HH:MM, séparées par des virgules (ex. 07:00, 13:00).');
      return;
    }
    final values = [
      _delay,
      _minSel,
      _maxSel,
      _minOdd,
      _maxOdd,
      _minProb,
      _window
    ].map(_num).toList();
    if (values.any((v) => v == null)) {
      setState(() => _error = 'Tous les champs numériques sont obligatoires.');
      return;
    }
    if (values[1]! > values[2]! || values[3]! > values[4]!) {
      setState(
          () => _error = 'Le minimum doit être inférieur ou égal au maximum.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      if (widget.profile.mode == 'scheduled') 'generate_times': times,
      'publish_delay_minutes': values[0]!.round(),
      'publish_mode': _review ? 'review' : 'auto',
      'criteria': {
        'min_selections': values[1]!.round(),
        'max_selections': values[2]!.round(),
        'min_total_odd': values[3],
        'max_total_odd': values[4],
        'min_model_probability': values[5]! / 100,
        'window_hours': values[6]!.round(),
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label,
            {bool numeric = true}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true),
          ),
        );
    Widget pair(Widget a, Widget b) => Row(children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b)
        ]);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Réglages · ${widget.profile.name}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            if (widget.profile.mode == 'scheduled')
              field(_times, 'Heures de génération (ex. 07:00, 13:00)',
                  numeric: false),
            field(_delay, 'Délai avant publication (minutes)'),
            pair(field(_minSel, 'Sélections min.'),
                field(_maxSel, 'Sélections max.')),
            pair(field(_minOdd, 'Cote totale min.'),
                field(_maxOdd, 'Cote totale max.')),
            pair(field(_minProb, 'Probabilité modèle min. (%)'),
                field(_window, 'Fenêtre de matchs (h)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Validation humaine avant publication'),
              value: _review,
              onChanged: (v) => setState(() => _review = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(onPressed: _save, child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
  }
}
