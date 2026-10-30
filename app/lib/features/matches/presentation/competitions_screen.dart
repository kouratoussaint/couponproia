import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'sports_widgets.dart';

/// Liste des compétitions suivies.
class CompetitionsScreen extends ConsumerWidget {
  const CompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final competitions = ref.watch(competitionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Compétitions')),
      body: competitions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(icon: Icons.cloud_off_outlined, title: 'Indisponible', body: userMessageFor(e)),
        data: (list) => list.isEmpty
            ? const InfoMessage(icon: Icons.emoji_events_outlined, title: 'Aucune compétition suivie')
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final c = list[i];
                  return ListTile(
                    leading: SportsLogo(url: c.logoUrl, size: 36, fallback: Icons.emoji_events_outlined),
                    title: Text(c.name),
                    subtitle: Text([
                      if (c.country != null) c.country!,
                      c.currentSeason == null ? 'saison non synchronisée' : 'saison ${_season(c.currentSeason!)}',
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.standingsFor(c.id)),
                  );
                },
              ),
      ),
    );
  }
}

String _season(int year) => '$year/${((year + 1) % 100).toString().padLeft(2, '0')}';

/// Classement d'une compétition (par groupe pour les phases de groupes).
class StandingsScreen extends ConsumerWidget {
  const StandingsScreen({super.key, required this.competitionId});

  final int competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final competition = ref.watch(competitionProvider(competitionId));
    return Scaffold(
      appBar: AppBar(title: Text(competition.valueOrNull?.name ?? 'Classement')),
      body: competition.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(icon: Icons.cloud_off_outlined, title: 'Indisponible', body: userMessageFor(e)),
        data: (c) {
          if (c == null) return const InfoMessage(icon: Icons.help_outline, title: 'Compétition introuvable');
          if (c.currentSeason == null) {
            return const InfoMessage(
              icon: Icons.hourglass_empty,
              title: 'Saison pas encore synchronisée',
              body: 'Le classement apparaîtra après la prochaine synchronisation quotidienne.',
            );
          }
          return _StandingsTable(competition: c);
        },
      ),
    );
  }
}

class _StandingsTable extends ConsumerWidget {
  const _StandingsTable({required this.competition});

  final CompetitionRef competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = ref.watch(standingsProvider((competition.id, competition.currentSeason!)));
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => InfoMessage(icon: Icons.cloud_off_outlined, title: 'Indisponible', body: userMessageFor(e)),
      data: (list) {
        if (list.isEmpty) {
          return const InfoMessage(
            icon: Icons.table_rows_outlined,
            title: 'Pas de classement',
            body: 'Le fournisseur ne publie pas de classement pour cette compétition, ou pas encore pour cette saison.',
          );
        }
        final groups = <String, List<StandingRow>>{};
        for (final r in list) {
          groups.putIfAbsent(r.group, () => []).add(r);
        }
        final header = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
        Widget cell(String text, {double width = 30, TextStyle? style, bool bold = false}) => SizedBox(
              width: width,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: (style ?? theme.textTheme.bodyMedium)?.copyWith(fontWeight: bold ? FontWeight.w700 : null),
              ),
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          children: [
            for (final entry in groups.entries) ...[
              if (groups.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: Text(entry.key, style: theme.textTheme.titleSmall),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            cell('#', width: 28, style: header),
                            Expanded(child: Text('Équipe', style: header)),
                            cell('J', style: header),
                            cell('G', style: header),
                            cell('N', style: header),
                            cell('P', style: header),
                            cell('Diff', width: 38, style: header),
                            cell('Pts', width: 36, style: header),
                          ],
                        ),
                      ),
                      for (final r in entry.value)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              cell('${r.rank}', width: 28),
                              Expanded(
                                child: Row(
                                  children: [
                                    SportsLogo(url: r.team.logoUrl, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(r.team.name, overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                              cell('${r.played}'),
                              cell('${r.win}'),
                              cell('${r.draw}'),
                              cell('${r.lose}'),
                              cell('${r.goalDiff > 0 ? '+' : ''}${r.goalDiff}', width: 38),
                              cell('${r.points}', width: 36, bold: true),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Source : API-Football · J joués, G gagnés, N nuls, P perdus.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}
