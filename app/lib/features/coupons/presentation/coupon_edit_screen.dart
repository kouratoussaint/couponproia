import 'package:flutter/material.dart';
import 'package:coupon_pro_ia/core/widgets/unsaved_changes_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../analysis/data/analysis_repository.dart';
import '../../lab/data/lab_repository.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/data/sports_models.dart';
import '../../matches/data/sports_repository.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/ai_consistency.dart';
import '../data/coupon_models.dart';
import '../data/coupon_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Confirmation quand une sélection contredit l'analyse IA : l'équipe peut passer outre.
Future<bool> confirmAiOverride(
    BuildContext context, List<String> items, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: BrandColors.orange),
      title: Text(tr('Contraire à l’analyse IA')),
      content: Text(trf(
          '{0}\n\nLes utilisateurs voient le pronostic de l’IA sur la fiche du match. Maintenir ce choix est noté au journal d’audit.',
          [items.map((i) => '• $i').join('\n')])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Revoir'))),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BrandColors.orange),
            onPressed: () => Navigator.pop(d, true),
            child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

class _Sel {
  _Sel(this.matchId, this.key, this.home, this.away, this.kickoffAt);

  final int matchId;
  String? key;
  final String home;
  final String away;
  final DateTime kickoffAt;
}

/// Modification d'un coupon généré avant sa publication (super administrateur).
class CouponEditScreen extends ConsumerStatefulWidget {
  const CouponEditScreen({super.key, required this.couponId});

  final String couponId;

  @override
  ConsumerState<CouponEditScreen> createState() => _CouponEditScreenState();
}

class _CouponEditScreenState extends ConsumerState<CouponEditScreen> {
  List<_Sel>? _sels;
  final _title = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  /// Saisie au chargement, pour savoir si quelque chose a changé (lot 27).
  String? _baseline;
  String _signature() => [
        _title.text,
        _note.text,
        for (final s in _sels ?? const <_Sel>[]) '${s.matchId}:${s.key}'
      ].join('\u0001');
  bool _dirty() => _baseline != null && _signature() != _baseline;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _init(Coupon c) {
    if (_sels != null) return;
    _sels = [
      for (final s in c.selections)
        _Sel(s.match.id, s.key, s.match.home, s.match.away, s.match.kickoffAt)
    ];
    _title.text = c.title;
    _baseline = _signature();
  }

  Future<void> _addMatch() async {
    final now = DateTime.now();
    final days = [dateOnly(now), dateOnly(now.add(const Duration(days: 1)))];
    final taken = {for (final s in _sels!) s.matchId};
    final picked = await showModalBottomSheet<MatchSummary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, controller) => Consumer(
          builder: (context, ref, _) {
            final all = [
              for (final d in days)
                ...?ref.watch(matchesOfDayProvider(d)).valueOrNull
            ]
                .where((m) =>
                    m.status == MatchStatus.scheduled &&
                    m.kickoffAt.isAfter(now.add(const Duration(minutes: 30))) &&
                    !taken.contains(m.id))
                .toList()
              ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
            return ListView(
              controller: controller,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(tr('Ajouter un match (aujourd’hui ou demain)')),
                ),
                for (final m in all)
                  ListTile(
                    title: Text('${m.home.name} – ${m.away.name}'),
                    subtitle: Text(
                        '${m.competition.name} · ${dayLabel(m.kickoffAt, now)} ${timeLabel(m.kickoffAt)}'),
                    onTap: () => Navigator.pop(sheet, m),
                  ),
                if (all.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(tr(
                        'Aucun autre match programmé à plus de 30 minutes.')),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _sels!.add(_Sel(picked.id, null, picked.home.name,
        picked.away.name, picked.kickoffAt)));
  }

  Future<void> _save({bool force = false}) async {
    final sels = _sels!;
    if (sels.isEmpty || sels.any((s) => s.key == null)) {
      showMessage(context, tr('Choisissez une issue pour chaque match.'),
          error: true);
      return;
    }
    if (_note.text.trim().length < 3) {
      showMessage(context, tr('Indiquez le motif de la modification.'),
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(couponRepositoryProvider).editCoupon(widget.couponId,
          selections: [for (final s in sels) (matchId: s.matchId, key: s.key!)],
          note: _note.text.trim(),
          title: _title.text.trim(),
          force: force);
      ref.invalidate(couponProvider(widget.couponId));
      invalidateCouponAdminLists(ref);
      if (mounted) {
        showMessage(
            context, tr('Coupon modifié : cotes et probabilités recalculées.'));
        context.pop();
      }
    } on CouponAiConflict catch (e) {
      if (mounted &&
          await confirmAiOverride(
              context, e.items, tr('Enregistrer quand même'))) {
        if (mounted) await _save(force: true);
      }
    } catch (e) {
      if (mounted) {
        showMessage(
            context, e is AnalysisException ? e.message : userMessageFor(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!perms.contains('coupons.edit')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Modifier le coupon'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Écran réservé au super administrateur')),
      );
    }
    final coupon = ref.watch(couponProvider(widget.couponId));
    return UnsavedChangesGuard(
        isDirty: _dirty,
        child: Scaffold(
          appBar: AppBar(title: Text(tr('Modifier le coupon'))),
          body: coupon.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => InfoMessage(
                icon: Icons.cloud_off_outlined,
                title: tr('Coupon indisponible'),
                body: userMessageFor(e)),
            data: (c) {
              if (c == null) {
                return InfoMessage(
                    icon: Icons.help_outline, title: tr('Coupon introuvable'));
              }
              if (!['pending_review', 'ready'].contains(c.status)) {
                return InfoMessage(
                    icon: Icons.lock_outline,
                    title: tr('Coupon non modifiable'),
                    body: tr(
                        'Un coupon publié est immuable : retirez-le, puis « Dupliquer et modifier ».'));
              }
              _init(c);
              return _form(context);
            },
          ),
        ));
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final sels = _sels!;
    double? total = 1;
    for (final s in sels) {
      final odds = ref.watch(latestOddsProvider(s.matchId)).valueOrNull;
      final o = odds?.where((o) => oddsKey(o) == s.key).firstOrNull;
      total = o == null || total == null ? null : total * o.median;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        TextField(
          controller: _title,
          maxLength: 120,
          decoration: InputDecoration(
              labelText: tr('Titre'), border: OutlineInputBorder()),
        ),
        SectionTitle(trf('Sélections ({0})', [sels.length]),
            trailing: Text(
                total == null
                    ? ''
                    : trf('cote indicative {0}', [decimal(total)]),
                style: theme.textTheme.labelLarge)),
        for (final (i, s) in sels.indexed)
          _SelectionEditor(
            sel: s,
            onChanged: (k) => setState(() => s.key = k),
            onRemove:
                sels.length > 1 ? () => setState(() => sels.removeAt(i)) : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sels.length >= 10 ? null : _addMatch,
            icon: const Icon(Icons.add),
            label: Text(tr('Ajouter un match')),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 200,
          decoration: InputDecoration(
              labelText: tr('Motif (journal d’audit)'),
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(tr('Enregistrer')),
        ),
        const SizedBox(height: 8),
        Text(tr('Le serveur relit les cotes médianes du moment, recalcule la cote totale, la probabilité, le risque et le résumé, et refuse un match à moins de 30 minutes du coup d’envoi. Le coupon garde son statut (à valider ou programmé).'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SelectionEditor extends ConsumerWidget {
  const _SelectionEditor(
      {required this.sel, required this.onChanged, this.onRemove});

  final _Sel sel;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final odds = ref.watch(latestOddsProvider(sel.matchId));
    final analysis =
        ref.watch(currentAnalysisProvider(sel.matchId)).valueOrNull;
    final ai = analysis?.ai;
    final picks = ai != null && ai.recommendationPossible
        ? [for (final p in ai.picks) p.key]
        : const <String>[];
    final bad =
        sel.key == null ? const <String>[] : aiContradictions(sel.key!, picks);
    final aiText = analysis == null
        ? tr('Pas encore d’analyse IA pour ce match')
        : picks.isEmpty
            ? tr('Analyse IA : aucun pronostic retenu')
            : trf('Pronostic IA : {0}', [
                picks
                    .map((k) => outcomeKeyLabel(k, sel.home, sel.away))
                    .join(', ')
              ]);
    return Card(
      shape: bad.isEmpty
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: BrandColors.orange, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${sel.home} – ${sel.away}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('${shortDate(sel.kickoffAt)} ${timeLabel(sel.kickoffAt)}',
                    style: theme.textTheme.labelMedium),
                IconButton(
                  tooltip: tr('Retirer ce match'),
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            Text(aiText,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: picks.isEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.primary)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: odds.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(userMessageFor(e)),
                data: (list) {
                  final keys = {for (final o in list) oddsKey(o)};
                  return DropdownButtonFormField<String>(
                    initialValue: keys.contains(sel.key) ? sel.key : null,
                    isExpanded: true,
                    hint: Text(tr('Choisir l’issue')),
                    decoration: InputDecoration(
                        labelText: tr('Issue'), border: OutlineInputBorder()),
                    items: [
                      for (final o in list)
                        DropdownMenuItem(
                          value: oddsKey(o),
                          child: Text(
                              '${outcomeKeyLabel(oddsKey(o), sel.home, sel.away)} · ${decimal(o.median)}'
                              '${aiContradictions(oddsKey(o), picks).isEmpty ? '' : '  ⚠'}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: onChanged,
                  );
                },
              ),
            ),
            if (bad.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 10),
                child: Text(
                    trf('Contraire au pronostic de l’IA ({0}).', [
                      bad
                          .map((k) => outcomeKeyLabel(k, sel.home, sel.away))
                          .join(', ')
                    ]),
                    style: const TextStyle(
                        color: BrandColors.orange,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}
