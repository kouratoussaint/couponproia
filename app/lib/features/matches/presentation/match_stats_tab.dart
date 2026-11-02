import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../analysis/data/analysis_format.dart';
import '../../analysis/presentation/analysis_section.dart';
import '../data/insights_models.dart';
import '../data/sports_format.dart';
import '../data/sports_models.dart';
import '../data/sports_repository.dart';
import 'match_tabs.dart';
import 'sports_widgets.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Onglet Stats : uniquement des résultats enregistrés (classement, forme, comparatif de saison,
/// séries en cours, confrontations directes).
class StatsTab extends ConsumerStatefulWidget {
  const StatsTab({super.key, required this.match});

  final MatchSummary match;

  @override
  ConsumerState<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<StatsTab> {
  bool _venue = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final insights = ref.watch(matchInsightsProvider(m.id));
    return insights.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(children: [
        InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Statistiques indisponibles'),
            body: userMessageFor(e)),
      ]),
      data: (ins) => ins == null
          ? ListView(children: [
              InfoMessage(
                  icon: Icons.help_outline,
                  title: tr('Statistiques introuvables'))
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                _Legend(match: m),
                _SummaryTiles(match: m, ins: ins),
                _FormCard(
                  match: m,
                  ins: ins,
                  venue: _venue,
                  onVenue: (v) => setState(() => _venue = v),
                ),
                if (ins.standings.isNotEmpty)
                  _StandingsCard(match: m, ins: ins),
                if (ins.homeSeason.played > 0 || ins.awaySeason.played > 0)
                  _SeasonCard(match: m, ins: ins),
                _StreaksCard(match: m, ins: ins),
                _H2hCard(match: m, ins: ins),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        trf(
                            'Chiffres calculés le {0} à {1} sur les résultats enregistrés (API-Football).',
                            [
                              shortDate(ins.computedAt),
                              timeLabel(ins.computedAt)
                            ]),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const ResponsibleNote(),
              ],
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    Widget dot(bool home) => Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(color: teamColor(home), shape: BoxShape.circle),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          dot(true),
          const SizedBox(width: 6),
          Expanded(
              child: Text(match.home.name,
                  style: style, overflow: TextOverflow.ellipsis)),
          Expanded(
              child: Text(match.away.name,
                  style: style,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          dot(false),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.title,
      required this.home,
      required this.away,
      this.footer});

  final String title;
  final String home;
  final String away;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(bool h, String v) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: teamColor(h), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(v,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        );
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(
            children: [
              Text(title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1,
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              line(true, home),
              const SizedBox(height: 2),
              line(false, away),
              if (footer != null)
                Text(footer!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

String _rank(StandingLine? s) =>
    s == null ? '—' : (s.rank == 1 ? '1er' : '${s.rank}e');

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.match, required this.ins});

  final MatchSummary match;
  final MatchInsights ins;

  @override
  Widget build(BuildContext context) {
    final h = ins.standingOf(match.home.id);
    final a = ins.standingOf(match.away.id);
    final h2h = ins.h2h;
    return Row(
      children: [
        _Tile(title: tr('Classement'), home: _rank(h), away: _rank(a)),
        _Tile(
          title: tr('Forme'),
          home: ins.homeForm.isEmpty
              ? '—'
              : '${formPoints(ins.homeForm)}/${ins.homeForm.length * 3} pts',
          away: ins.awayForm.isEmpty
              ? '—'
              : '${formPoints(ins.awayForm)}/${ins.awayForm.length * 3} pts',
        ),
        _Tile(
          title: tr('Face-à-face'),
          home: trf('{0} V', [h2h.homeWins]),
          away: trf('{0} V', [h2h.awayWins]),
          footer: trf('{0} N', [h2h.draws]),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard(
      {required this.match,
      required this.ins,
      required this.venue,
      required this.onVenue});

  final MatchSummary match;
  final MatchInsights ins;
  final bool venue;
  final ValueChanged<bool> onVenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = venue ? ins.homeAtHome : ins.homeForm;
    final away = venue ? ins.awayAway : ins.awayForm;
    Widget team(bool isHome, String name, List<FormEntry> form) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: teamColor(isHome), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(name,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis)),
                  Text(
                      form.isEmpty
                          ? ''
                          : trf('{0} pts sur {1}',
                              [formPoints(form), form.length * 3]),
                      style: theme.textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 6),
              if (form.isEmpty)
                Text(tr('Aucun match enregistré'),
                    style: theme.textTheme.bodySmall)
              else ...[
                FormChips(results: [for (final e in form) e.letter]),
                const SizedBox(height: 6),
                for (final e in form)
                  Text(
                    '${e.letter} · ${shortDate(e.kickoffAt)} · ${e.atHome ? tr('contre') : tr('chez')} ${e.opponent} '
                    '${e.goalsFor}-${e.goalsAgainst} · ${e.competition}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Forme'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('Tous les matchs'))),
                ButtonSegment(
                    value: true, label: Text(tr('Domicile / extérieur'))),
              ],
              selected: {venue},
              onSelectionChanged: (s) => onVenue(s.first),
            ),
            team(
                true,
                venue
                    ? trf('{0} à domicile', [match.home.name])
                    : match.home.name,
                home),
            team(
                false,
                venue
                    ? trf('{0} à l’extérieur', [match.away.name])
                    : match.away.name,
                away),
            const SizedBox(height: 6),
            Text(tr('Du plus récent au plus ancien · toutes compétitions.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _StandingsCard extends StatelessWidget {
  const _StandingsCard({required this.match, required this.ins});

  final MatchSummary match;
  final MatchInsights ins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = ins.standings;
    final ids = {match.home.id, match.away.id};
    // Haut du tableau, bas du tableau et les deux équipes (sans tout afficher).
    final keep = <int>{};
    for (var i = 0; i < rows.length; i++) {
      if (i < 5 || i >= rows.length - 3 || ids.contains(rows[i].teamId)) {
        keep.add(i);
      }
      if (ids.contains(rows[i].teamId)) {
        if (i > 0) keep.add(i - 1);
        if (i < rows.length - 1) keep.add(i + 1);
      }
    }
    final h = ins.standingOf(match.home.id);
    final a = ins.standingOf(match.away.id);
    Color zoneColor(StandingZone z) => switch (z) {
          StandingZone.top => scheme.primary,
          StandingZone.qualification => scheme.primary.withValues(alpha: 0.5),
          StandingZone.relegation => scheme.error,
          StandingZone.none => Colors.transparent,
        };
    final head =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final children = <Widget>[];
    int? last;
    for (final i in keep.toList()..sort()) {
      if (last != null && i > last + 1) {
        children.add(Center(child: Text('…', style: head)));
      }
      last = i;
      final r = rows[i];
      final mine = ids.contains(r.teamId);
      children.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: mine ? scheme.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: zoneColor(r.zone), width: 3)),
        ),
        child: Row(
          children: [
            SizedBox(
                width: 26,
                child: Text('${r.rank}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: mine ? FontWeight.w800 : null))),
            if (mine) ...[
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      color: teamColor(r.teamId == match.home.id),
                      shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Expanded(
                child: Text(r.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: mine ? FontWeight.w800 : null))),
            SizedBox(
                width: 28,
                child: Text('${r.played}', textAlign: TextAlign.end)),
            SizedBox(
                width: 44,
                child: Text('${r.goalDiff > 0 ? '+' : ''}${r.goalDiff}',
                    textAlign: TextAlign.end)),
            SizedBox(
                width: 40,
                child: Text('${r.points}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      ));
    }
    String line(StandingLine? s, String name) {
      if (s == null) return '';
      final z = zoneLabel(s.description);
      return '$name · ${_rank(s)}${z.isEmpty ? '' : ' · $z'}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(tr('Classement'),
                        style: theme.textTheme.titleMedium)),
                TextButton(
                  onPressed: () => context
                      .push(AppRoutes.standingsFor(match.competition.id)),
                  child: Text(tr('Tout voir')),
                ),
              ],
            ),
            for (final (s, name) in [
              (h, match.home.name),
              (a, match.away.name)
            ])
              if (s != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(line(s, name), style: theme.textTheme.bodyMedium),
                ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(width: 34, child: Text('#', style: head)),
                Expanded(child: Text(tr('Équipe'), style: head)),
                SizedBox(
                    width: 28,
                    child: Text('J', style: head, textAlign: TextAlign.end)),
                SizedBox(
                    width: 44,
                    child: Text(tr('Diff.'),
                        style: head, textAlign: TextAlign.end)),
                SizedBox(
                    width: 40,
                    child:
                        Text(tr('Pts'), style: head, textAlign: TextAlign.end)),
              ],
            ),
            ...children,
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              children: [
                _zoneKey(context, scheme.primary, tr('Places qualificatives')),
                _zoneKey(context, scheme.error, tr('Relégation')),
              ],
            ),
            if (ins.standingsUpdatedAt != null) ...[
              const SizedBox(height: 8),
              SourceChip(
                  label: trf('API-Football · classement du {0} {1}', [
                shortDate(ins.standingsUpdatedAt!),
                timeLabel(ins.standingsUpdatedAt!)
              ])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _zoneKey(BuildContext context, Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 3, height: 14, color: c),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.match, required this.ins});

  final MatchSummary match;
  final MatchInsights ins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = ins.homeSeason;
    final a = ins.awaySeason;
    String frac(int n, int d) => '$n/$d';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Comparatif de la saison'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                trf('{0} · {1} {2} matchs · {3} {4} matchs', [
                  match.competition.name,
                  match.home.name,
                  h.played,
                  match.away.name,
                  a.played
                ]),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            _DuelBar(
                label: tr('Buts marqués par match'),
                home: h.goalsForAvg,
                away: a.goalsForAvg,
                max: 4,
                homeText: decimal(h.goalsForAvg, 1),
                awayText: decimal(a.goalsForAvg, 1)),
            _DuelBar(
                label: tr('Buts encaissés par match'),
                home: h.goalsAgainstAvg,
                away: a.goalsAgainstAvg,
                max: 4,
                homeText: decimal(h.goalsAgainstAvg, 1),
                awayText: decimal(a.goalsAgainstAvg, 1)),
            _DuelBar(
                label: tr('Matchs sans encaisser'),
                home: h.played == 0 ? 0 : h.cleanSheets / h.played,
                away: a.played == 0 ? 0 : a.cleanSheets / a.played,
                max: 1,
                homeText: frac(h.cleanSheets, h.played),
                awayText: frac(a.cleanSheets, a.played)),
            _DuelBar(
                label: tr('Matchs à 3 buts ou plus'),
                home: h.played == 0 ? 0 : h.threePlus / h.played,
                away: a.played == 0 ? 0 : a.threePlus / a.played,
                max: 1,
                homeText: frac(h.threePlus, h.played),
                awayText: frac(a.threePlus, a.played)),
            _DuelBar(
                label: tr('Les deux équipes ont marqué'),
                home: h.played == 0 ? 0 : h.btts / h.played,
                away: a.played == 0 ? 0 : a.btts / a.played,
                max: 1,
                homeText: frac(h.btts, h.played),
                awayText: frac(a.btts, a.played)),
          ],
        ),
      ),
    );
  }
}

/// Barres face à face : l'équipe qui reçoit à gauche, l'équipe visiteuse à droite.
class _DuelBar extends StatelessWidget {
  const _DuelBar({
    required this.label,
    required this.home,
    required this.away,
    required this.max,
    required this.homeText,
    required this.awayText,
  });

  final String label;
  final double home;
  final double away;
  final double max;
  final String homeText;
  final String awayText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = theme.colorScheme.surfaceContainerHighest;
    Widget bar(double v, bool isHome) => Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 10,
              color: track,
              alignment: isHome ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (v / max).clamp(0.0, 1.0),
                child: Container(color: teamColor(isHome)),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                  width: 44,
                  child: Text(homeText,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700))),
              bar(home, true),
              const SizedBox(width: 6),
              bar(away, false),
              SizedBox(
                  width: 44,
                  child: Text(awayText,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreaksCard extends StatelessWidget {
  const _StreaksCard({required this.match, required this.ins});

  final MatchSummary match;
  final MatchInsights ins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <(bool, String, Streak, String)>[
      for (final s in usefulStreaks(ins.homeStreaks).take(2))
        (true, match.home.name, s, tr('toutes compétitions')),
      for (final s in usefulStreaks(ins.homeAtHomeStreaks).take(1))
        (true, match.home.name, s, tr('à domicile')),
      for (final s in usefulStreaks(ins.awayStreaks).take(2))
        (false, match.away.name, s, tr('toutes compétitions')),
      for (final s in usefulStreaks(ins.awayAwayStreaks).take(1))
        (false, match.away.name, s, tr('à l’extérieur')),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Séries en cours'), style: theme.textTheme.titleMedium),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('Aucune série d’au moins 3 matchs en cours.'),
                    style: theme.textTheme.bodyMedium),
              ),
            for (final (isHome, name, s, scope) in items)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: teamColor(isHome),
                              shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '$name · ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            TextSpan(text: s.label),
                          ])),
                          Text(
                            [
                              scope,
                              if (s.from != null && s.to != null)
                                trf('du {0} au {1}',
                                    [shortDate(s.from!), shortDate(s.to!)]),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(tr('« Au moins » : la série couvre tous les matchs enregistrés et peut être plus longue.'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _H2hCard extends StatelessWidget {
  const _H2hCard({required this.match, required this.ins});

  final MatchSummary match;
  final MatchInsights ins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = ins.h2h;
    Widget box(String n, String label, bool? isHome) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(n,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: theme.textTheme.labelSmall),
                if (isHome != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: teamColor(isHome), shape: BoxShape.circle)),
                  ),
              ],
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Confrontations directes'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            if (h.count == 0)
              Text(
                  tr('Aucune confrontation dans les résultats enregistrés (saisons synchronisées).'),
                  style: theme.textTheme.bodyMedium)
            else ...[
              Row(
                children: [
                  box('${h.homeWins}', tr('Victoires'), true),
                  box('${h.draws}', tr('Nuls'), null),
                  box('${h.awayWins}', tr('Victoires'), false),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                trf('Sur {0} confrontation{1}{2}{3}.', [
                  h.count,
                  h.count > 1 ? 's' : '',
                  h.first == null || h.last == null
                      ? ''
                      : trf(', du {0}/{1} au {2}/{3}', [
                          shortDate(h.first!),
                          h.first!.year,
                          shortDate(h.last!),
                          h.last!.year
                        ]),
                  h.avgGoals == null
                      ? ''
                      : trf(' · {0} buts par match en moyenne',
                          [decimal(h.avgGoals!, 1)])
                ]),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                  trf('Résultat pour {0}, du plus récent au plus ancien',
                      [match.home.name]),
                  style: theme.textTheme.labelMedium),
              for (final x in h.matches)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      FormChips(results: [x.letterForMatchHome], size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${x.home} ${x.homeGoals}-${x.awayGoals} ${x.away}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text(
                                '${shortDate(x.kickoffAt)}/${x.kickoffAt.year} · ${x.competition}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
