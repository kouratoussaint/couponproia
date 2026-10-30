import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../analysis/data/analysis_repository.dart';
import '../../analysis/presentation/analysis_section.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'sports_widgets.dart';

/// Fiche d'un match : en-tête, cotes, forme récente, confrontations, classement.
/// Chaque bloc indique sa source et ses limites ; les estimations viennent du moteur
/// d'analyse (bloc « Analyse IA »), calculées côté serveur.
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final int matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    return Scaffold(
      appBar: AppBar(title: Text(match.valueOrNull?.competition.name ?? 'Match')),
      body: match.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(icon: Icons.cloud_off_outlined, title: 'Match indisponible', body: userMessageFor(e)),
        data: (m) => m == null
            ? const InfoMessage(icon: Icons.help_outline, title: 'Match introuvable')
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(matchProvider(matchId));
                  ref.invalidate(latestOddsProvider(matchId));
                  ref.invalidate(storedAnalysisProvider(matchId));
                  await ref.read(matchProvider(matchId).future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    _Header(match: m),
                    const SizedBox(height: 12),
                    AnalysisSection(match: m),
                    _OddsSection(match: m),
                    _FormSection(match: m),
                    _HeadToHeadSection(match: m),
                    _StandingsSection(match: m),
                    const SizedBox(height: 16),
                    Text(
                      'Source : API-Football · données mises à jour le ${shortDate(m.sourceUpdatedAt)} '
                      'à ${timeLabel(m.sourceUpdatedAt)}. Les pronostics sont des estimations ; aucun gain n’est garanti.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = match;
    Widget team(TeamRef t) => Expanded(
          child: Column(
            children: [
              SportsLogo(url: t.logoUrl, size: 56),
              const SizedBox(height: 8),
              Text(t.name, textAlign: TextAlign.center, style: theme.textTheme.titleSmall, maxLines: 2),
            ],
          ),
        );
    final center = m.hasScore
        ? '${m.homeGoals} - ${m.awayGoals}'
        : timeLabel(m.kickoffAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              [if (m.round != null) m.round!, '${dayLabel(m.kickoffAt, DateTime.now())} ${shortDate(m.kickoffAt)}']
                  .join(' · '),
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                team(m.home),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Column(
                    children: [
                      Text(center, style: theme.textTheme.headlineMedium?.copyWith(
                        color: m.isLive ? theme.colorScheme.primary : null,
                      )),
                      Text(statusLabel(m), style: theme.textTheme.labelMedium),
                      if (m.htHomeGoals != null && m.htAwayGoals != null && m.status != MatchStatus.scheduled)
                        Text('Mi-temps ${m.htHomeGoals}-${m.htAwayGoals}', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                team(m.away),
              ],
            ),
            if (m.venue != null || m.referee != null) ...[
              const SizedBox(height: 12),
              Text(
                [if (m.venue != null) m.venue!, if (m.referee != null) 'Arbitre : ${m.referee}'].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OddsSection extends ConsumerWidget {
  const _OddsSection({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final odds = ref.watch(latestOddsProvider(match.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Cotes'),
        odds.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucune cote relevée pour ce match. Les cotes sont relevées deux fois par jour '
                    'pour les matchs des 48 heures à venir.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }
            final byMarket = oddsByMarket(list);
            final latest = list.map((o) => o.capturedAt).reduce((a, b) => a.isAfter(b) ? a : b);
            final books = list.map((o) => o.bookmakers).reduce((a, b) => a > b ? a : b);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in byMarket.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                        child: Text(marketTitles[entry.key] ?? entry.key, style: theme.textTheme.labelLarge),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final o in entry.value) _OddTile(odd: o)],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Cote médiane de $books bookmakers au maximum (« max » = meilleure cote), '
                      'relevé du ${shortDate(latest)} à ${timeLabel(latest)}. '
                      'Les cotes changent et peuvent différer de celles de votre opérateur.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OddTile extends StatelessWidget {
  const _OddTile({required this.odd});

  final OddsLine odd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(outcomeLabel(odd), style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
          Text(formatOdd(odd.median), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
          Text('max ${formatOdd(odd.best)}', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _FormSection extends ConsumerWidget {
  const _FormSection({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget teamForm(TeamRef team) {
      final recent = ref.watch(recentMatchesProvider((team.id, match.kickoffAt)));
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SportsLogo(url: team.logoUrl, size: 28),
        title: Text(team.name, overflow: TextOverflow.ellipsis),
        subtitle: recent.when(
          loading: () => const Text('…'),
          error: (e, _) => Text(userMessageFor(e)),
          data: (list) {
            final form = formFor(team.id, list);
            return form.isEmpty
                ? const Text('Aucun match terminé dans les données synchronisées')
                : Padding(padding: const EdgeInsets.only(top: 6), child: FormChips(results: form));
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Forme récente (5 derniers matchs)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [teamForm(match.home), teamForm(match.away)]),
          ),
        ),
      ],
    );
  }
}

class _HeadToHeadSection extends ConsumerWidget {
  const _HeadToHeadSection({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final h2h = ref.watch(headToHeadProvider((match.home.id, match.away.id, match.kickoffAt)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Confrontations directes'),
        Card(
          child: h2h.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(userMessageFor(e))),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Aucune confrontation dans les données synchronisées (saison en cours des compétitions suivies).',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : Column(
                    children: [
                      for (final m in list)
                        ListTile(
                          dense: true,
                          title: Text('${m.home.name}  ${m.homeGoals} - ${m.awayGoals}  ${m.away.name}'),
                          subtitle: Text('${shortDate(m.kickoffAt)}/${m.kickoffAt.year} · ${m.competition.name}'),
                          onTap: () => context.push(AppRoutes.matchDetailFor(m.id)),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _StandingsSection extends ConsumerWidget {
  const _StandingsSection({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final table = ref.watch(standingsProvider((match.competition.id, match.season)));
    return table.maybeWhen(
      data: (rows) {
        final mine = rows.where((r) => r.team.id == match.home.id || r.team.id == match.away.id).toList();
        if (mine.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'Classement',
              trailing: TextButton(
                onPressed: () => context.push(AppRoutes.standingsFor(match.competition.id)),
                child: const Text('Tout voir'),
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (final r in mine)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Text('${r.rank}', style: theme.textTheme.labelMedium),
                      ),
                      title: Text(r.team.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${r.played} J · ${r.win} G ${r.draw} N ${r.lose} P · diff. ${r.goalDiff > 0 ? '+' : ''}${r.goalDiff}'
                        '${r.group.isNotEmpty && rows.map((x) => x.group).toSet().length > 1 ? ' · ${r.group}' : ''}',
                      ),
                      trailing: Text('${r.points} pts', style: theme.textTheme.titleSmall),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
