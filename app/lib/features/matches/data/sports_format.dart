// Mise en forme et calculs d'affichage (fonctions pures, testées unitairement).
import 'sports_models.dart';

const _weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Début et fin (exclue) d'une journée locale, en UTC pour les requêtes.
(DateTime, DateTime) utcRangeForLocalDay(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  return (start.toUtc(), end.toUtc());
}

String two(int n) => n.toString().padLeft(2, '0');

String timeLabel(DateTime local) => '${two(local.hour)}:${two(local.minute)}';

String shortDate(DateTime local) => '${two(local.day)}/${two(local.month)}';

/// « 31/10/2026 à 18:05 » : date complète avec l'année et l'heure.
String dateTimeLabel(DateTime local) =>
    '${shortDate(local)}/${local.year} à ${timeLabel(local)}';

String dayLabel(DateTime day, DateTime today) {
  final diff = dateOnly(day).difference(dateOnly(today)).inDays;
  if (diff == 0) return 'Aujourd’hui';
  if (diff == 1) return 'Demain';
  if (diff == -1) return 'Hier';
  final year = day.year == today.year ? '' : '/${day.year}';
  return '${_weekdays[day.weekday - 1]} ${shortDate(day)}$year';
}

/// Jour de départ du calendrier en mode archive : même jour et même mois dans la
/// saison d'archive (une saison va de juillet à juin).
DateTime archiveDay(DateTime today, int season) {
  final year = today.month >= 7 ? season : season + 1;
  final lastDay = DateTime(year, today.month + 1, 0).day;
  return DateTime(year, today.month, today.day > lastDay ? lastDay : today.day);
}

/// « 2024/25 »
String seasonLabel(int season) =>
    '$season/${((season + 1) % 100).toString().padLeft(2, '0')}';

String statusLabel(MatchSummary m) {
  switch (m.status) {
    case MatchStatus.scheduled:
      return timeLabel(m.kickoffAt);
    case MatchStatus.live:
      if (m.statusShort == 'HT') return 'Mi-temps';
      if (m.statusShort == 'P') return 'Tirs au but';
      return m.elapsed == null ? 'En cours' : '${m.elapsed}’';
    case MatchStatus.finished:
      if (m.statusShort == 'AET') return 'Terminé (a.p.)';
      if (m.statusShort == 'PEN') return 'Terminé (t.a.b.)';
      return 'Terminé';
    case MatchStatus.postponed:
      return 'Reporté';
    case MatchStatus.cancelled:
      return 'Annulé';
    case MatchStatus.abandoned:
      return 'Arrêté';
    case MatchStatus.interrupted:
      return 'Interrompu';
    case MatchStatus.awarded:
      return 'Sur tapis vert';
    case MatchStatus.unknown:
      return '—';
  }
}

/// Résultat d'un match terminé du point de vue d'une équipe : V, N ou D.
String? resultFor(int teamId, MatchSummary m) {
  if (m.status != MatchStatus.finished || !m.hasScore) return null;
  final isHome = m.home.id == teamId;
  if (!isHome && m.away.id != teamId) return null;
  final mine = isHome ? m.homeGoals! : m.awayGoals!;
  final theirs = isHome ? m.awayGoals! : m.homeGoals!;
  if (mine > theirs) return 'V';
  if (mine < theirs) return 'D';
  return 'N';
}

/// Forme récente : résultats du plus récent au plus ancien.
List<String> formFor(int teamId, List<MatchSummary> matches) {
  final sorted = [...matches]
    ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
  return [
    for (final m in sorted)
      if (resultFor(teamId, m) case final r?) r,
  ];
}

/// Regroupe les matchs par compétition, dans l'ordre d'apparition.
List<(CompetitionRef, List<MatchSummary>)> groupByCompetition(
    List<MatchSummary> matches) {
  final order = <int>[];
  final byId = <int, (CompetitionRef, List<MatchSummary>)>{};
  for (final m in matches) {
    final entry = byId[m.competition.id];
    if (entry == null) {
      order.add(m.competition.id);
      byId[m.competition.id] = (m.competition, [m]);
    } else {
      entry.$2.add(m);
    }
  }
  return [for (final id in order) byId[id]!];
}

const _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'õ': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ñ': 'n',
};

String simplify(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

/// Recherche insensible à la casse et aux accents sur les équipes et la compétition.
bool matchesQuery(MatchSummary m, String query) {
  final q = simplify(query.trim());
  if (q.isEmpty) return true;
  return simplify(m.home.name).contains(q) ||
      simplify(m.away.name).contains(q) ||
      simplify(m.competition.name).contains(q);
}

/// Cote au format français : 1,95.
String formatOdd(double odd) => odd.toStringAsFixed(2).replaceAll('.', ',');

String formatLine(double line) => line.toStringAsFixed(1).replaceAll('.', ',');

/// Libellé court d'une issue (dans le contexte de son marché).
String outcomeLabel(OddsLine o) {
  switch (o.marketCode) {
    case '1X2':
      return const {'HOME': '1', 'DRAW': 'X', 'AWAY': '2'}[o.outcomeCode] ??
          o.outcomeCode;
    case 'DC':
      return o.outcomeCode;
    case 'OU':
      final line = o.line == null ? '' : ' ${formatLine(o.line!)}';
      return o.outcomeCode == 'OVER' ? 'Plus de$line' : 'Moins de$line';
    case 'BTTS':
      return o.outcomeCode == 'YES' ? 'Oui' : 'Non';
  }
  return o.outcomeCode;
}

const marketTitles = {
  '1X2': 'Résultat du match',
  'DC': 'Double chance',
  'OU': 'Plus / moins de buts',
  'BTTS': 'Les deux équipes marquent',
};

const _outcomeOrder = [
  'HOME',
  'DRAW',
  'AWAY',
  '1X',
  '12',
  'X2',
  'OVER',
  'UNDER',
  'YES',
  'NO'
];

/// Cotes rangées par marché, issues dans l'ordre habituel (1, X, 2…), lignes croissantes.
Map<String, List<OddsLine>> oddsByMarket(List<OddsLine> odds) {
  final result = <String, List<OddsLine>>{};
  for (final code in marketTitles.keys) {
    final list = odds.where((o) => o.marketCode == code).toList()
      ..sort((a, b) {
        final byLine = (a.line ?? 0).compareTo(b.line ?? 0);
        if (byLine != 0) return byLine;
        return _outcomeOrder
            .indexOf(a.outcomeCode)
            .compareTo(_outcomeOrder.indexOf(b.outcomeCode));
      });
    if (list.isNotEmpty) result[code] = list;
  }
  return result;
}
