import 'package:coupon_pro_ia/features/matches/data/sports_format.dart';
import 'package:coupon_pro_ia/features/matches/data/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _matchJson({
  int id = 1,
  int homeId = 10,
  int awayId = 20,
  String status = 'finished',
  String? short = 'FT',
  int? homeGoals = 2,
  int? awayGoals = 1,
  String kickoff = '2026-10-25T15:00:00Z',
  int competitionId = 100,
  String competitionName = 'Premier League',
}) =>
    {
      'id': id,
      'season': 2026,
      'round': 'Journée 9',
      'kickoff_at': kickoff,
      'status': status,
      'status_short': short,
      'elapsed': status == 'live' ? 67 : null,
      'home_goals': homeGoals,
      'away_goals': awayGoals,
      'ht_home_goals': null,
      'ht_away_goals': null,
      'venue': null,
      'referee': null,
      'source_updated_at': '2026-10-30T04:00:00Z',
      'competition': {'id': competitionId, 'name': competitionName, 'country': 'England', 'logo_url': null, 'current_season': 2026},
      'home': {'id': homeId, 'name': 'Équipe Alpha', 'logo_url': null},
      'away': {'id': awayId, 'name': 'Beta FC', 'logo_url': 'https://x/b.png'},
    };

void main() {
  group('Lecture des données Supabase', () {
    test('match', () {
      final m = MatchSummary.fromJson(_matchJson());
      expect(m.status, MatchStatus.finished);
      expect(m.hasScore, isTrue);
      expect(m.home.name, 'Équipe Alpha');
      expect(m.away.logoUrl, 'https://x/b.png');
      expect(m.competition.currentSeason, 2026);
    });

    test('statut inconnu toléré', () {
      expect(MatchStatus.parse('bizarre'), MatchStatus.unknown);
    });

    test('cote : les numeric arrivent en entier ou en décimal', () {
      final o = OddsLine.fromJson({
        'market_code': 'OU',
        'outcome_code': 'OVER',
        'line': 2.5,
        'odd_median': 2,
        'odd_best': 2.15,
        'bookmakers_count': 9,
        'captured_at': '2026-10-30T07:00:00Z',
      });
      expect(o.median, 2.0);
      expect(outcomeLabel(o), 'Plus de 2,5');
      expect(formatOdd(o.best), '2,15');
    });
  });

  group('Statuts affichés', () {
    test('en cours, mi-temps, terminé, reporté', () {
      expect(statusLabel(MatchSummary.fromJson(_matchJson(status: 'live', short: '2H'))), '67’');
      expect(statusLabel(MatchSummary.fromJson(_matchJson(status: 'live', short: 'HT'))), 'Mi-temps');
      expect(statusLabel(MatchSummary.fromJson(_matchJson())), 'Terminé');
      expect(statusLabel(MatchSummary.fromJson(_matchJson(status: 'postponed', short: 'PST'))), 'Reporté');
    });
  });

  group('Forme récente', () {
    test('V / N / D du point de vue de l’équipe, du plus récent au plus ancien', () {
      final matches = [
        MatchSummary.fromJson(_matchJson(id: 1, kickoff: '2026-10-01T15:00:00Z', homeGoals: 0, awayGoals: 0)),
        MatchSummary.fromJson(_matchJson(id: 2, kickoff: '2026-10-20T15:00:00Z', homeGoals: 3, awayGoals: 1)),
        MatchSummary.fromJson(_matchJson(id: 3, kickoff: '2026-10-10T15:00:00Z', homeId: 30, awayId: 10, homeGoals: 2, awayGoals: 0)),
        MatchSummary.fromJson(_matchJson(id: 4, kickoff: '2026-10-25T15:00:00Z', status: 'postponed', short: 'PST', homeGoals: null, awayGoals: null)),
      ];
      expect(formFor(10, matches), ['V', 'D', 'N']);
      expect(formFor(20, matches), ['D', 'N']);
    });
  });

  group('Calendrier', () {
    test('libellés de jour', () {
      final today = DateTime(2026, 10, 30);
      expect(dayLabel(DateTime(2026, 10, 30), today), 'Aujourd’hui');
      expect(dayLabel(DateTime(2026, 10, 31), today), 'Demain');
      expect(dayLabel(DateTime(2026, 10, 29), today), 'Hier');
      expect(dayLabel(DateTime(2026, 11, 2), today), 'lun. 02/11');
    });

    test('une journée locale couvre 24 h', () {
      final (from, to) = utcRangeForLocalDay(DateTime(2026, 10, 30, 18));
      expect(to.difference(from), const Duration(hours: 24));
      expect(from.isUtc, isTrue);
    });
  });

  group('Recherche et regroupement', () {
    test('insensible aux accents et à la casse', () {
      final m = MatchSummary.fromJson(_matchJson());
      expect(matchesQuery(m, 'equipe alp'), isTrue);
      expect(matchesQuery(m, 'BETA'), isTrue);
      expect(matchesQuery(m, 'premier'), isTrue);
      expect(matchesQuery(m, 'gamma'), isFalse);
      expect(matchesQuery(m, '  '), isTrue);
    });

    test('groupes par compétition dans l’ordre d’apparition', () {
      final groups = groupByCompetition([
        MatchSummary.fromJson(_matchJson(id: 1, competitionId: 2, competitionName: 'Ligue des champions')),
        MatchSummary.fromJson(_matchJson(id: 2, competitionId: 1, competitionName: 'Ligue 1')),
        MatchSummary.fromJson(_matchJson(id: 3, competitionId: 2, competitionName: 'Ligue des champions')),
      ]);
      expect(groups.map((g) => g.$1.name), ['Ligue des champions', 'Ligue 1']);
      expect(groups.first.$2.length, 2);
    });

    test('cotes rangées par marché et par issue', () {
      OddsLine o(String market, String outcome, [double? line]) => OddsLine(
            marketCode: market,
            outcomeCode: outcome,
            line: line,
            median: 2,
            best: 2.1,
            bookmakers: 5,
            capturedAt: DateTime(2026),
          );
      final byMarket = oddsByMarket([
        o('1X2', 'AWAY'),
        o('OU', 'UNDER', 2.5),
        o('1X2', 'HOME'),
        o('OU', 'OVER', 1.5),
        o('1X2', 'DRAW'),
      ]);
      expect(byMarket.keys, ['1X2', 'OU']);
      expect(byMarket['1X2']!.map(outcomeLabel), ['1', 'X', '2']);
      expect(byMarket['OU']!.map(outcomeLabel), ['Plus de 1,5', 'Moins de 2,5']);
    });
  });
}
