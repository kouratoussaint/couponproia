// Lecture d'une analyse pour la fiche match : pronostic principal, faits vérifiés (avec source et
// heure), scénario défavorable. Uniquement des chiffres déjà présents dans la fiche du moteur ou
// dans les résultats enregistrés : rien n'est inventé ni arrondi vers le haut.
import '../../matches/data/insights_models.dart';
import '../../matches/data/sports_format.dart';
import 'analysis_format.dart';
import 'analysis_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Pronostic mis en avant : celui de l'IA s'il existe, sinon l'issue la plus probable du modèle.
class MainPick {
  const MainPick({
    required this.key,
    required this.probability,
    required this.fromAi,
    this.justification,
    this.oddMedian,
    this.impliedProbability,
    this.edge,
  });

  final String key;
  final double probability;

  /// true : pronostic retenu par l'IA (validé) ; false : simple issue la plus probable du modèle.
  final bool fromAi;
  final String? justification;
  final double? oddMedian;
  final double? impliedProbability;
  final double? edge;

  double get fairOddValue => 1 / probability;
}

FicheOddsLine? lineFor(AnalysisFiche f, String key) {
  for (final l in f.marketLines) {
    if (l.key == key) return l;
  }
  return null;
}

MainPick? mainPickOf(MatchAnalysis a) {
  final f = a.fiche;
  final ai = a.ai;
  if (ai != null && ai.recommendationPossible && ai.picks.isNotEmpty) {
    final p = ai.picks.first;
    final line = lineFor(f, p.key);
    return MainPick(
      key: p.key,
      probability: p.modelProbability,
      fromAi: true,
      justification: p.justification,
      oddMedian: p.oddMedian ?? line?.oddMedian,
      impliedProbability: p.impliedProbability ?? line?.impliedProbability,
      edge: p.edge ?? line?.edge,
    );
  }
  const keys = ['1X2.HOME', '1X2.DRAW', '1X2.AWAY'];
  String? best;
  for (final k in keys) {
    final p = f.p(k);
    if (p != null && (best == null || p > f.p(best)!)) best = k;
  }
  if (best == null) return null;
  final line = lineFor(f, best);
  return MainPick(
    key: best,
    probability: f.p(best)!,
    fromAi: false,
    oddMedian: line?.oddMedian,
    impliedProbability: line?.impliedProbability,
    edge: line?.edge,
  );
}

/// Issues contraires d'un pronostic, avec leur probabilité estimée.
List<(String, double)> alternativesOf(
    String key, AnalysisFiche f, String home, String away) {
  final parts = key.split('.');
  List<String> keys;
  switch (parts.first) {
    case '1X2':
      keys = ['1X2.HOME', '1X2.DRAW', '1X2.AWAY']..remove(key);
    case 'DC':
      keys = [
        switch (parts.length > 1 ? parts[1] : '') {
          '1X' => '1X2.AWAY',
          'X2' => '1X2.HOME',
          '12' => '1X2.DRAW',
          _ => '',
        }
      ];
    case 'OU':
      final line = parts.sublist(2).join('.');
      keys = ['OU.${parts[1] == 'OVER' ? 'UNDER' : 'OVER'}.$line'];
    case 'BTTS':
      keys = ['BTTS.${parts[1] == 'YES' ? 'NO' : 'YES'}'];
    case 'DNB':
      keys = [parts[1] == 'HOME' ? '1X2.AWAY' : '1X2.HOME'];
    case 'TTH' || 'TTA':
      final line = parts.sublist(2).join('.');
      keys = ['${parts[0]}.${parts[1] == 'OVER' ? 'UNDER' : 'OVER'}.$line'];
    default:
      keys = const [];
  }
  return [
    for (final k in keys)
      if (f.p(k) != null) (outcomeKeyLabel(k, home, away), f.p(k)!)
  ];
}

/// Encadré « Si ça ne passe pas » : rappel chiffré que l'issue contraire reste possible.
String downsideText(MainPick pick, AnalysisFiche f, String home, String away) {
  final label = outcomeKeyLabel(pick.key, home, away);
  final miss = 1 - pick.probability;
  final others = alternativesOf(pick.key, f, home, away);
  return [
    trf('« {0} » est estimé à {1} : l’issue contraire reste possible {2}, même quand l’analyse est juste.',
        [label, pct(pick.probability), frequencyLabel(miss)]),
    if (others.isNotEmpty)
      trf('Scénarios contraires selon le modèle : {0}.',
          [others.map((o) => '${o.$1} ${pct(o.$2)}').join(', ')]),
    tr('Ce sont des estimations : jouez uniquement ce que vous pouvez vous permettre de perdre.'),
  ].join(' ');
}

/// Un fait affiché dans l'onglet Analyse, toujours avec sa source et l'heure de la donnée.
class VerifiedFact {
  const VerifiedFact(
      {required this.title, required this.text, required this.source, this.at});

  final String title;
  final String text;
  final String source;
  final DateTime? at;

  String get sourceLabel =>
      at == null ? source : '$source · ${shortDate(at!)} ${timeLabel(at!)}';
}

String _lowerFirst(String s) =>
    s.startsWith(tr('A ')) || s.startsWith(tr('Au '))
        ? s[0].toLowerCase() + s.substring(1)
        : s;

String _ord(int rank) => rank == 1 ? '1er' : '${rank}e';
String _plural(int n, String word) => '$n $word${n > 1 ? 's' : ''}';

List<VerifiedFact> buildFacts({
  required String home,
  required String away,
  required int homeId,
  required int awayId,
  MatchInsights? insights,
  MatchAnalysis? analysis,
}) {
  final facts = <VerifiedFact>[];
  final ins = insights;
  if (ins != null) {
    final h = ins.standingOf(homeId);
    final a = ins.standingOf(awayId);
    if (h != null && a != null) {
      facts.add(VerifiedFact(
        title: tr('Classement'),
        text: trf(
            '{0} est {1} avec {2} points en {3} matchs ; {4} est {5} avec {6} points en {7} matchs.',
            [
              home,
              _ord(h.rank),
              h.points,
              h.played,
              away,
              _ord(a.rank),
              a.points,
              a.played
            ]),
        source: 'API-Football',
        at: ins.standingsUpdatedAt,
      ));
    }
    if (ins.homeForm.isNotEmpty && ins.awayForm.isNotEmpty) {
      facts.add(VerifiedFact(
        title: tr('Forme récente'),
        text: trf(
            'Sur leurs derniers matchs : {0} a pris {1} points sur {2}, {3} {4} sur {5}.',
            [
              home,
              formPoints(ins.homeForm),
              ins.homeForm.length * 3,
              away,
              formPoints(ins.awayForm),
              ins.awayForm.length * 3
            ]),
        source: tr('Résultats enregistrés'),
        at: ins.computedAt,
      ));
    }
    if (ins.homeAtHome.isNotEmpty && ins.awayAway.isNotEmpty) {
      facts.add(VerifiedFact(
        title: tr('À domicile et à l’extérieur'),
        text: trf(
            '{0} : {1} points sur {2} lors de ses {3} dernier{7} matchs à domicile ; {4} : {5} sur {6} à l’extérieur.',
            [
              home,
              formPoints(ins.homeAtHome),
              ins.homeAtHome.length * 3,
              ins.homeAtHome.length,
              away,
              formPoints(ins.awayAway),
              ins.awayAway.length * 3,
              ins.homeAtHome.length > 1 ? 's' : '',
            ]),
        source: tr('Résultats enregistrés'),
        at: ins.computedAt,
      ));
    }
    final h2h = ins.h2h;
    if (h2h.count > 0) {
      facts.add(VerifiedFact(
        title: tr('Confrontations directes'),
        text: trf('{0}{1} : {2} de {3}, {4}, {5} de {6}{7}.', [
          _plural(h2h.count, tr('confrontation')),
          h2h.first == null ? '' : trf(' depuis {0}', [h2h.first!.year]),
          _plural(h2h.homeWins, tr('victoire')),
          home,
          _plural(h2h.draws, tr('nul')),
          _plural(h2h.awayWins, tr('victoire')),
          away,
          h2h.avgGoals == null
              ? ''
              : trf(', {0} buts par match en moyenne',
                  [decimal(h2h.avgGoals!, 1)])
        ]),
        source: tr('Résultats enregistrés'),
        at: ins.computedAt,
      ));
    }
    for (final (team, streaks) in [
      (home, usefulStreaks(ins.homeStreaks)),
      (away, usefulStreaks(ins.awayStreaks)),
    ]) {
      if (streaks.isNotEmpty) {
        facts.add(VerifiedFact(
          title: tr('Série en cours'),
          text: '$team : ${_lowerFirst(streaks.first.label)}.',
          source: tr('Résultats enregistrés'),
          at: ins.computedAt,
        ));
      }
    }
  }
  final a = analysis;
  if (a != null) {
    final f = a.fiche;
    final source = tr('Modèle Coupon Pro IA');
    facts.add(VerifiedFact(
      title: tr('Buts attendus'),
      text: trf('Le modèle attend {0} buts pour {1} et {2} pour {3}.', [
        decimal(f.expectedGoalsHome),
        home,
        decimal(f.expectedGoalsAway),
        away
      ]),
      source: source,
      at: a.createdAt,
    ));
    final draw = f.p('1X2.DRAW');
    if (draw != null) {
      facts.add(VerifiedFact(
        title: tr('Le match nul'),
        text: trf('Le nul est estimé à {0}, soit {1}.',
            [pct(draw), frequencyLabel(draw)]),
        source: source,
        at: a.createdAt,
      ));
    }
    final pick = mainPickOf(a);
    if (pick != null &&
        pick.impliedProbability != null &&
        pick.oddMedian != null) {
      facts.add(VerifiedFact(
        title: tr('Modèle et marché'),
        text: trf(
            'Pour « {0} », les cotes donnent {1} (cote {2}) et le modèle {3}.',
            [
              outcomeKeyLabel(pick.key, home, away),
              pct(pick.impliedProbability!),
              decimal(pick.oddMedian!),
              pct(pick.probability)
            ]),
        source: tr('Cotes médianes des bookmakers'),
        at: f.marketCapturedAt,
      ));
    }
  }
  return facts;
}
