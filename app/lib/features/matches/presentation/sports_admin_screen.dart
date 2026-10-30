import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../system/system_providers.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'sports_widgets.dart';

const _jobLabels = {
  'daily': 'Calendriers, résultats et classements',
  'odds': 'Cotes des 48 prochaines heures',
  'live': 'Scores en direct',
};

const _statusLabels = {
  'running': 'En cours',
  'success': 'Réussie',
  'partial': 'Partielle',
  'failed': 'Échec',
  'skipped': 'Ignorée',
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
      showMessage(context, 'Synchronisation lancée. Le résultat apparaît dans le journal sous peu.');
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
    final permissions = ref.watch(myPermissionsProvider).valueOrNull ?? const <String>{};
    if (!permissions.contains('sports.configure')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Données sportives')),
        body: const InfoMessage(icon: Icons.lock_outline, title: 'Accès réservé aux administrateurs'),
      );
    }
    final runs = ref.watch(syncRunsProvider);
    final budget = ref.watch(dailyBudgetProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Données sportives'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(syncRunsProvider),
          ),
        ],
      ),
      body: runs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(icon: Icons.cloud_off_outlined, title: 'Journal indisponible', body: userMessageFor(e)),
        data: (list) {
          final today = dateOnly(DateTime.now());
          final usedToday = list
              .where((r) => !r.startedAt.toUtc().isBefore(DateTime.utc(today.year, today.month, today.day)))
              .fold<int>(0, (sum, r) => sum + r.requestsUsed);
          final remaining = list.where((r) => r.requestsRemaining != null).map((r) => r.requestsRemaining).firstOrNull;
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
                        Text('Fournisseur : API-Football', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Requêtes aujourd’hui (UTC) : $usedToday${budget == null ? '' : ' / $budget autorisées'}'),
                        Text('Quota restant annoncé par le fournisseur : ${remaining ?? 'inconnu'}'),
                        const SizedBox(height: 8),
                        Text(
                          'Planification : calendriers à 4 h, cotes à 7 h et 15 h, scores en direct toutes les 15 min.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Lancer maintenant'),
                for (final entry in _jobLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: _launching == null ? () => _launch(entry.key) : null,
                      icon: _launching == entry.key
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow),
                      label: Text(entry.value),
                    ),
                  ),
                const SectionTitle('Journal (20 derniers passages)'),
                if (list.isEmpty)
                  const InfoMessage(icon: Icons.history, title: 'Aucune synchronisation pour l’instant'),
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
                Expanded(child: Text(_jobLabels[run.job] ?? run.job, style: theme.textTheme.titleSmall)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusLabels[run.status] ?? run.status, style: TextStyle(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${shortDate(run.startedAt)} à ${timeLabel(run.startedAt)}'
              '${duration == null ? '' : ' · ${duration.inSeconds} s'}'
              ' · ${run.requestsUsed} requête(s) · ${run.itemsUpserted} élément(s)',
              style: theme.textTheme.bodySmall,
            ),
            if (run.error != null) ...[
              const SizedBox(height: 4),
              Text(run.error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
