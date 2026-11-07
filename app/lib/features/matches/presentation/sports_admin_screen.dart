import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../system/system_providers.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'sports_widgets.dart';
import '../../admin/presentation/competitions_admin_screen.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

final _jobLabels = {
  'daily': tr('Calendriers, résultats et classements'),
  'odds': tr('Cotes des 48 prochaines heures'),
  'live': tr('Scores en direct'),
  'catalog': tr('Catalogue des compétitions du fournisseur'),
};

/// Tâches lancées automatiquement seulement (affichées dans le journal).
final _autoJobLabels = {
  'matchday': tr('Compositions et absents'),
};

final _statusLabels = {
  'running': tr('En cours'),
  'success': tr('Réussie'),
  'partial': tr('Partielle'),
  'failed': tr('Échec'),
  'skipped': tr('Ignorée'),
};

/// Administration des données sportives : consommation du quota, journal des
/// synchronisations et lancement manuel. Réservé à la permission sports.configure.
class SportsAdminScreen extends ConsumerStatefulWidget {
  const SportsAdminScreen({super.key});

  @override
  ConsumerState<SportsAdminScreen> createState() => _SportsAdminScreenState();
}

class _SportsAdminScreenState extends ConsumerState<SportsAdminScreen> {
  String? _launching;

  Future<void> _launch(String job) async {
    setState(() => _launching = job);
    try {
      await ref.read(sportsRepositoryProvider).triggerSync(job);
      if (!mounted) return;
      showMessage(context,
          tr('Synchronisation lancée. Le résultat apparaît dans le journal sous peu.'));
      await Future<void>.delayed(const Duration(seconds: 4));
      ref.invalidate(syncRunsProvider);
    } catch (e) {
      if (mounted) showMessage(context, userMessageFor(e), error: true);
    } finally {
      if (mounted) setState(() => _launching = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions =
        ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!permissions.contains('sports.configure')) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Données sportives'))),
        body: InfoMessage(
            icon: Icons.lock_outline,
            title: tr('Accès réservé aux administrateurs')),
      );
    }
    final runs = ref.watch(syncRunsProvider);
    final budget = ref.watch(dailyBudgetProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Données sportives')),
        actions: [
          IconButton(
            tooltip: tr('Actualiser'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(syncRunsProvider),
          ),
        ],
      ),
      body: runs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Journal indisponible'),
            body: userMessageFor(e)),
        data: (list) {
          final today = dateOnly(DateTime.now());
          final usedToday = list
              .where((r) => !r.startedAt
                  .toUtc()
                  .isBefore(DateTime.utc(today.year, today.month, today.day)))
              .fold<int>(0, (sum, r) => sum + r.requestsUsed);
          final remaining = list
              .where((r) => r.requestsRemaining != null)
              .map((r) => r.requestsRemaining)
              .firstOrNull;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(syncRunsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Fournisseur : API-Football'),
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(trf('Requêtes aujourd’hui (UTC) : {0}{1}', [
                          usedToday,
                          budget == null
                              ? ''
                              : trf(' / {0} autorisées', [budget])
                        ])),
                        Text(trf(
                            'Quota restant annoncé par le fournisseur : {0}',
                            [remaining ?? 'inconnu'])),
                        const SizedBox(height: 8),
                        Text(
                          tr('Planification : calendriers à 4 h, cotes à 6 h, 12 h et 18 h, compositions et absents toutes les 10 min, scores en direct toutes les 30 s pendant les matchs, catalogue le lundi à 3 h 10.'),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const CompetitionsAdminScreen())),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: Text(tr('Compétitions')),
                ),
                SectionTitle(tr('Lancer maintenant')),
                for (final entry in _jobLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed:
                          _launching == null ? () => _launch(entry.key) : null,
                      icon: _launching == entry.key
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow),
                      label: Text(entry.value),
                    ),
                  ),
                SectionTitle(tr('Journal (20 derniers passages)')),
                if (list.isEmpty)
                  InfoMessage(
                      icon: Icons.history,
                      title: tr('Aucune synchronisation pour l’instant')),
                for (final r in list) _RunTile(run: r),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final SyncRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (run.status) {
      'success' => scheme.primary,
      'partial' || 'running' => scheme.secondary,
      'failed' => scheme.error,
      _ => scheme.outline,
    };
    final duration = run.finishedAt?.difference(run.startedAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(
                        _jobLabels[run.job] ??
                            _autoJobLabels[run.job] ??
                            run.job,
                        style: theme.textTheme.titleSmall)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusLabels[run.status] ?? run.status,
                      style: TextStyle(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              trf('{0} à {1}{2} · {3} requête(s) · {4} élément(s)', [
                shortDate(run.startedAt),
                timeLabel(run.startedAt),
                duration == null ? '' : trf(' · {0} s', [duration.inSeconds]),
                run.requestsUsed,
                run.itemsUpserted
              ]),
              style: theme.textTheme.bodySmall,
            ),
            if (run.error != null) ...[
              const SizedBox(height: 4),
              Text(run.error!,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
