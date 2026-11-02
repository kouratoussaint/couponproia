import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/super_admin_note.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/history_filter.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../analysis/data/analysis_format.dart';
import '../../coupons/presentation/bookmaker_actions.dart';
import '../../simulator/presentation/sim_entries.dart';
import '../../coupons/presentation/coupon_widgets.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_widgets.dart';
import '../../studio/data/studio_models.dart';
import '../../../core/theme/solid_buttons.dart';
import '../../billing/credit_costs.dart';
import '../../journal/data/journal_repository.dart';
import '../../simulator/presentation/stake_simulator_sheet.dart';
import '../data/assistant_models.dart';
import '../../system/system_providers.dart';
import '../data/assistant_repository.dart';
import '../data/my_coupons_view.dart';

/// Mes coupons : coupons enregistrés depuis l'assistant ou le laboratoire.
/// Bandeau « Mon bilan », coupons en cours d'abord, puis coupons terminés par jour.
/// Appui long (ou ⋮) : laboratoire, simulation, carnet, partage, renommer, supprimer.
class MyCouponsScreen extends ConsumerStatefulWidget {
  const MyCouponsScreen({super.key, this.embedded = false});

  /// Dans l'onglet « Mes coupons » de l'Assistant IA : sans barre de titre.
  final bool embedded;

  @override
  ConsumerState<MyCouponsScreen> createState() => _MyCouponsScreenState();
}

class _MyCouponsScreenState extends ConsumerState<MyCouponsScreen> {
  HistoryFilter _filter = const HistoryFilter();

  @override
  Widget build(BuildContext context) {
    final coupons = ref.watch(savedCouponsProvider);
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Mes coupons')),
      floatingActionButton: coupons.valueOrNull?.isNotEmpty ?? false
          ? FloatingActionButton.extended(
              heroTag: 'my-coupons-create',
              onPressed: () => showCreateCouponChoice(context),
              icon: const Icon(Icons.add),
              label: const Text('Créer un coupon'),
            )
          : null,
      body: coupons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
            body: userMessageFor(e)),
        data: (list) {
          if (list.isEmpty) {
            return InfoMessage(
              icon: Icons.bookmarks_outlined,
              title: 'Aucun coupon enregistré',
              body:
                  'Demandez un coupon à l’assistant ou composez-le dans le laboratoire, puis enregistrez-le.',
              action: FilledButton.icon(
                onPressed: () => showCreateCouponChoice(context),
                icon: const Icon(Icons.add),
                label: const Text('Créer un coupon'),
              ),
            );
          }
          final shown = [
            for (final c in list)
              if (_filter.accepts(c.result, c.createdAt)) c
          ];
          final inProgress = [
            for (final c in shown)
              if (c.result == null) c
          ];
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(savedCouponsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                MyCouponsSummaryCard(summary: summarize(list)),
                const SizedBox(height: 8),
                HistoryFilterBar(
                    value: _filter,
                    onChanged: (v) => setState(() => _filter = v)),
                const SizedBox(height: 4),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun coupon pour ce filtre.'),
                  ),
                if (inProgress.isNotEmpty) ...[
                  _DayTitle(
                      label: 'En cours',
                      detail:
                          '${inProgress.length} coupon${inProgress.length > 1 ? 's' : ''}'),
                  for (final c in inProgress) MyCouponTile(coupon: c),
                ],
                for (final (day, items) in decidedByDay(shown)) ...[
                  _DayTitle(
                    label: () {
                      final l = dayLabel(day, DateTime.now());
                      return l.contains('/') ? l : '$l ${shortDate(day)}';
                    }(),
                    detail: [
                      '${items.where((c) => c.result == 'won').length} gagné(s)',
                      '${items.where((c) => c.result == 'lost').length} perdu(s)',
                      if (items.any((c) => c.result == 'void'))
                        '${items.where((c) => c.result == 'void').length} annulé(s)',
                    ].join(' · '),
                  ),
                  for (final c in items) MyCouponTile(coupon: c),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bandeau « Mon bilan » : vos coupons enregistrés, pertes comprises.
class MyCouponsSummaryCard extends StatelessWidget {
  const MyCouponsSummaryCard({super.key, required this.summary});

  final MyCouponsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = summary;
    Widget stat(String value, String label, [Color? color]) => Expanded(
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
            ),
            Text(label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mon bilan',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              stat('${s.total}', 'coupons'),
              stat('${s.won}', s.won > 1 ? 'gagnés' : 'gagné', scheme.primary),
              stat('${s.lost}', s.lost > 1 ? 'perdus' : 'perdu', scheme.error),
              stat(s.successRate == null ? '–' : pct(s.successRate!),
                  'réussite'),
              stat(s.averageOdd == null ? '–' : decimal(s.averageOdd!),
                  'cote moyenne'),
            ]),
            const SizedBox(height: 6),
            Text(
              '${s.inProgress} en cours${s.voided > 0 ? ' · ${s.voided} annulé(s), hors réussite' : ''}. '
              'Pertes comprises ; les résultats passés ne préjugent pas des suivants.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTitle extends StatelessWidget {
  const _DayTitle({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(detail,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Ligne d'un de vos coupons : pastille de résultat, titre, deux matchs au plus,
/// dates complètes ; la cote est verte seulement si le coupon est gagné.
class MyCouponTile extends ConsumerWidget {
  const MyCouponTile({super.key, required this.coupon});

  final UserCoupon coupon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = coupon;
    final (icon, color, label) = switch (c.result) {
      'won' => (Icons.check, scheme.primary, 'Gagné'),
      'lost' => (Icons.close, scheme.error, 'Perdu'),
      'void' => (Icons.remove, scheme.outline, 'Annulé'),
      _ => (Icons.schedule, scheme.onSurfaceVariant, 'En cours'),
    };
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final labCost = paysCreditsAsFree(ref.watch(myCreditsProvider).valueOrNull)
        ? ref.watch(labCostProvider)
        : 0;
    void actions() => showMyCouponActions(context, ref, c, labCost: labCost);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => context.push(AppRoutes.myCouponFor(c.id)),
        onLongPress: actions,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
          child: Row(
            children: [
              Semantics(
                label: label,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayTitle(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (c.selections.isNotEmpty)
                      Text(matchesLine(c),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: muted),
                    Text(myCouponDateLine(c), style: muted),
                    Text(
                        'Probabilité estimée ${pct(c.combinedProbability)}'
                        '${c.isPublished ? ' · publié' : ''}',
                        style: muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      decimal(c.result == 'won' && c.settledOdd != null
                          ? c.settledOdd!
                          : c.totalOdd),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.result == 'won'
                              ? scheme.primary
                              : scheme.onSurfaceVariant)),
                  Text(label,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: color, fontWeight: FontWeight.w700)),
                ],
              ),
              IconButton(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert),
                onPressed: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Créer un coupon » : avec l'assistant ou à la main dans le laboratoire.
Future<void> showCreateCouponChoice(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Avec l’assistant'),
              subtitle: const Text('Décrivez le coupon voulu, l’IA le compose'),
              onTap: () {
                Navigator.pop(sheet);
                _openAssistantTab(context, 0, AppRoutes.assistant);
              },
            ),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Dans le laboratoire'),
              subtitle: const Text('Choisissez vous-même chaque sélection'),
              onTap: () {
                Navigator.pop(sheet);
                _openAssistantTab(context, 2, AppRoutes.assistantLab);
              },
            ),
          ],
        ),
      ),
    );

/// Dans l'Assistant IA, change d'onglet ; sinon, ouvre l'onglet voulu.
void _openAssistantTab(BuildContext context, int index, String route) {
  final tabs = DefaultTabController.maybeOf(context);
  if (tabs != null && tabs.length == 3) {
    tabs.animateTo(index);
  } else {
    context.go(route);
  }
}

/// Actions d'un de vos coupons. Un coupon publié reste immuable : ni renommer ni supprimer.
/// `labCost` : crédits par calcul du laboratoire (0 avec un forfait payant).
Future<void> showMyCouponActions(
    BuildContext context, WidgetRef ref, UserCoupon c,
    {int labCost = 0}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(displayTitle(c),
                  style: Theme.of(sheet).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Ouvrir dans le laboratoire'),
              subtitle: Text(labCost > 0
                  ? 'Analyser, optimiser, simuler : ${creditsLabel(labCost)} par calcul'
                  : 'Analyser, optimiser, simuler'),
              onTap: () => Navigator.pop(sheet, 'lab'),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Simuler une mise'),
              onTap: () => Navigator.pop(sheet, 'simulate'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Noter dans mon carnet'),
              onTap: () => Navigator.pop(sheet, 'journal'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Partager (copier le coupon)'),
              onTap: () => Navigator.pop(sheet, 'share'),
            ),
            if (!c.isPublished) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Renommer'),
                onTap: () => Navigator.pop(sheet, 'rename'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(sheet).colorScheme.error),
                title: Text('Supprimer',
                    style: TextStyle(color: Theme.of(sheet).colorScheme.error)),
                onTap: () => Navigator.pop(sheet, 'delete'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'lab':
      context.push(AppRoutes.labFor(c.id));
    case 'simulate':
      showStakeSimulator(context, [userCouponSim(c)]);
    case 'journal':
      await _noteInJournal(context, ref, c);
    case 'share':
      await Clipboard.setData(ClipboardData(
          text: couponShareText(displayTitle(c), c.totalOdd, c.selections,
              (s) => outcomeKeyLabel(s.key, s.match.home, s.match.away))));
      if (context.mounted) {
        showMessage(context, 'Coupon copié : collez-le où vous voulez.');
      }
    case 'rename':
      await _rename(context, ref, c);
    case 'delete':
      await _delete(context, ref, c);
  }
}

Future<void> _noteInJournal(
    BuildContext context, WidgetRef ref, UserCoupon c) async {
  final input = userCouponSim(c);
  final cur = currencyLabel(ref.read(publicSettingsProvider).valueOrNull);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => JournalEntryDialog(
        title: displayTitle(c),
        stake: 1000,
        odd: input.currentOdd ?? input.odd,
        currency: cur,
        onSave: (stake, odd, note) => ref
            .read(journalRepositoryProvider)
            .add(input, stake: stake, odd: odd, note: note)),
  );
  if (saved != true || !context.mounted) return;
  ref.invalidate(journalProvider);
  showMessage(context, 'Pari noté dans votre carnet.');
}

Future<void> _rename(BuildContext context, WidgetRef ref, UserCoupon c) async {
  final controller = TextEditingController(text: displayTitle(c));
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Renommer le coupon'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Nom du coupon'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(d, controller.text.trim()),
            child: const Text('Enregistrer')),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty || !context.mounted) return;
  final bad = forbiddenWordIn(name);
  if (bad != null) {
    showMessage(context, 'Nom refusé : « $bad ». Pas de promesse de résultat.',
        error: true);
    return;
  }
  try {
    await ref.read(assistantRepositoryProvider).rename(c.id, name);
    ref.invalidate(savedCouponsProvider);
    ref.invalidate(userCouponProvider(c.id));
  } catch (e) {
    if (context.mounted) showMessage(context, userMessageFor(e), error: true);
  }
}

Future<void> _delete(BuildContext context, WidgetRef ref, UserCoupon c) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Supprimer ce coupon ?'),
      content: Text('« ${displayTitle(c)} » sera effacé de Mes coupons.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Annuler')),
        FilledButton(
            style: solidButtonStyle(d, SolidTone.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Supprimer')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(assistantRepositoryProvider).deleteCoupon(c.id);
    ref.invalidate(savedCouponsProvider);
  } catch (e) {
    if (context.mounted) showMessage(context, userMessageFor(e), error: true);
  }
}

/// Détail d'un coupon de l'utilisateur.
class MyCouponDetailScreen extends ConsumerWidget {
  const MyCouponDetailScreen({super.key, required this.couponId});

  final String couponId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coupon = ref.watch(userCouponProvider(couponId));
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon coupon'),
        actions: [
          if (coupon.valueOrNull case final c? when c.selections.isNotEmpty)
            IconButton(
              tooltip: 'Créer un visuel',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => context.push(AppRoutes.studioFor('user', c.id)),
            ),
        ],
      ),
      body: coupon.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Indisponible',
            body: userMessageFor(e)),
        data: (c) => c == null
            ? const InfoMessage(
                icon: Icons.help_outline, title: 'Coupon introuvable')
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayTitle(c),
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('Cote totale ${decimal(c.totalOdd)}',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: theme.colorScheme.primary)),
                          Text(
                              'Probabilité estimée par le modèle : ${pct(c.combinedProbability)}'
                              '${c.impliedProbability == null ? '' : ' (marché : ${pct(c.impliedProbability!)})'}'),
                          const SizedBox(height: 8),
                          RiskBadge(risk: c.riskLevel),
                        ],
                      ),
                    ),
                  ),
                  for (final w in c.warnings)
                    Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text('⚠ $w', style: muted)),
                  const SectionTitle('Sélections'),
                  for (final s in c.selections) SelectionCard(selection: s),
                  if (c.summary.isNotEmpty) ...[
                    const SectionTitle('Analyse'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.summary),
                            for (final v in c.vigilance)
                              Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('• $v',
                                      style: theme.textTheme.bodySmall)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (c.isPublished) ...[
                    const SizedBox(height: 8),
                    PublishedBadge(publishedAt: c.publishedAt!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!c.isPublished && c.status != 'archived')
                        FilledButton.icon(
                          onPressed: () => _publish(context, ref, c.id),
                          icon: const Icon(Icons.public),
                          label: const Text('Publier sur mon profil Tipster'),
                        ),
                      if (!c.isSaved)
                        FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(assistantRepositoryProvider)
                                .setStatus(c.id, 'saved');
                            ref.invalidate(userCouponProvider(c.id));
                            ref.invalidate(savedCouponsProvider);
                          },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Enregistrer'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutes.labFor(c.id)),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Laboratoire'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                            text: couponShareText(
                                c.title,
                                c.totalOdd,
                                c.selections,
                                (s) => outcomeKeyLabel(
                                    s.key, s.match.home, s.match.away)),
                          ));
                          if (context.mounted) {
                            showMessage(context,
                                'Coupon copié : collez-le où vous voulez.');
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copier pour partager'),
                      ),
                      SimulateButton(choices: () => [userCouponSim(c)]),
                      FilledButton.tonalIcon(
                        onPressed: () => copyForBookmaker(
                            context, ref, c.title, c.totalOdd, c.selections),
                        icon: const Icon(Icons.content_paste_go_outlined),
                        label: const Text('Copier pour mon bookmaker'),
                      ),
                      if (!c.isPublished)
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(assistantRepositoryProvider)
                                  .deleteCoupon(c.id);
                              ref.invalidate(savedCouponsProvider);
                              if (context.mounted) context.pop();
                            } catch (e) {
                              if (context.mounted) {
                                showMessage(context, userMessageFor(e),
                                    error: true);
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Supprimer'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${myCouponDateLine(c)}. '
                    'Cotes relevées au moment de la création : elles ont pu changer. Estimations, sans garantie de gain.',
                    style: muted,
                    textAlign: TextAlign.center,
                  ),
                  if (ref
                          .watch(myPermissionsProvider)
                          .valueOrNull
                          ?.contains('ai.providers') ??
                      false)
                    SuperAdminNote(text: 'moteur ${c.engineVersion}'),
                ],
              ),
      ),
    );
  }
}

/// Publication sur le profil Tipster : définitive, avant le premier coup d'envoi.
Future<void> _publish(
    BuildContext context, WidgetRef ref, String couponId) async {
  final comment = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Publier ce coupon ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Il apparaîtra sur votre profil Tipster et dans le fil de vos abonnés. '
              'Une fois publié, il ne peut plus être modifié ni supprimé : son résultat comptera '
              'dans vos statistiques, qu’il soit gagné ou perdu.'),
          const SizedBox(height: 12),
          TextField(
            controller: comment,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
                labelText: 'Votre commentaire (facultatif)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Publier')),
      ],
    ),
  );
  if (ok == true) {
    final bad = forbiddenWordIn(comment.text);
    if (bad != null) {
      if (context.mounted) {
        showMessage(
            context, 'Texte refusé : « $bad ». Pas de promesse de résultat.',
            error: true);
      }
    } else {
      try {
        await ref
            .read(communityRepositoryProvider)
            .publishCoupon(couponId, comment.text);
        ref.invalidate(userCouponProvider(couponId));
        ref.invalidate(savedCouponsProvider);
        ref.invalidate(feedProvider);
        if (context.mounted) {
          showMessage(context, 'Coupon publié sur votre profil Tipster.');
        }
      } catch (e) {
        if (context.mounted) {
          showMessage(context, communityErrorMessage(e), error: true);
        }
      }
    }
  }
  comment.dispose();
}
