// Lecture d'une analyse pour la fiche match : pronostic principal, faits vérifiés (avec source et
// heure), scénario défavorable. Uniquement des chiffres déjà présents dans la fiche du moteur ou
// dans les résultats enregistrés : rien n'est inventé ni arrondi vers le haut.
import '../../matches/data/insights_models.dart';
import '../../matches/data/sports_format.dart';
import 'analysis_format.dart';
import 'analysis_models.dart';

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
    '« $label » est estimé à ${pct(pick.probability)} : l’issue contraire reste possible '
        '${frequencyLabel(miss)}, même quand l’analyse est juste.',
    if (others.isNotEmpty)
      'Scénarios contraires selon le modèle : '
          '${others.map((o) => '${o.$1} ${pct(o.$2)}').join(', ')}.',
    'Ce sont des estimations : jouez uniquement ce que vous pouvez vous permettre de perdre.',
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

String _lowerFirst(String s) => s.startsWith('A ') || s.startsWith('Au ')
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
        title: 'Classement',
        text:
            '$home est ${_ord(h.rank)} avec ${h.points} points en ${h.played} matchs ; '
            '$away est ${_ord(a.rank)} avec ${a.points} points en ${a.played} matchs.',
        source: 'API-Football',
        at: ins.standingsUpdatedAt,
      ));
    }
    if (ins.homeForm.isNotEmpty && ins.awayForm.isNotEmpty) {
      facts.add(VerifiedFact(
        title: 'Forme récente',
        text:
            'Sur leurs derniers matchs : $home a pris ${formPoints(ins.homeForm)} points sur '
            '${ins.homeForm.length * 3}, $away ${formPoints(ins.awayForm)} sur ${ins.awayForm.length * 3}.',
        source: 'Résultats enregistrés',
        at: ins.computedAt,
      ));
    }
    if (ins.homeAtHome.isNotEmpty && ins.awayAway.isNotEmpty) {
      facts.add(VerifiedFact(
        title: 'À domicile et à l’extérieur',
        text:
            '$home : ${formPoints(ins.homeAtHome)} points sur ${ins.homeAtHome.length * 3} '
            'lors de ses ${_plural(ins.homeAtHome.length, 'dernier')} matchs à domicile ; '
            '$away : ${formPoints(ins.awayAway)} sur ${ins.awayAway.length * 3} à l’extérieur.',
        source: 'Résultats enregistrés',
        at: ins.computedAt,
      ));
    }
    final h2h = ins.h2h;
    if (h2h.count > 0) {
      facts.add(VerifiedFact(
        title: 'Confrontations directes',
        text: '${_plural(h2h.count, 'confrontation')}'
            '${h2h.first == null ? '' : ' depuis ${h2h.first!.year}'} : '
            '${_plural(h2h.homeWins, 'victoire')} de $home, ${_plural(h2h.draws, 'nul')}, '
            '${_plural(h2h.awayWins, 'victoire')} de $away'
            '${h2h.avgGoals == null ? '' : ', ${decimal(h2h.avgGoals!, 1)} buts par match en moyenne'}.',
        source: 'Résultats enregistrés',
        at: ins.computedAt,
      ));
    }
    for (final (team, streaks) in [
      (home, usefulStreaks(ins.homeStreaks)),
      (away, usefulStreaks(ins.awayStreaks)),
    ]) {
      if (streaks.isNotEmpty) {
        facts.add(VerifiedFact(
          title: 'Série en cours',
          text: '$team : ${_lowerFirst(streaks.first.label)}.',
          source: 'Résultats enregistrés',
          at: ins.computedAt,
        ));
      }
    }
  }
  final a = analysis;
  if (a != null) {
    final f = a.fiche;
    final source = 'Modèle Coupon Pro IA';
    facts.add(VerifiedFact(
      title: 'Buts attendus',
      text:
          'Le modèle attend ${decimal(f.expectedGoalsHome)} buts pour $home et '
          '${decimal(f.expectedGoalsAway)} pour $away.',
      source: source,
      at: a.createdAt,
    ));
    final draw = f.p('1X2.DRAW');
    if (draw != null) {
      facts.add(VerifiedFact(
        title: 'Le match nul',
        text: 'Le nul est estimé à ${pct(draw)}, soit ${frequencyLabel(draw)}.',
        source: source,
        at: a.createdAt,
      ));
    }
    final pick = mainPickOf(a);
    if (pick != null &&
        pick.impliedProbability != null &&
        pick.oddMedian != null) {
      facts.add(VerifiedFact(
        title: 'Modèle et marché',
        text:
            'Pour « ${outcomeKeyLabel(pick.key, home, away)} », les cotes donnent '
            '${pct(pick.impliedProbability!)} (cote ${decimal(pick.oddMedian!)}) et le modèle '
            '${pct(pick.probability)}.',
        source: 'Cotes médianes des bookmakers',
        at: f.marketCapturedAt,
      ));
    }
  }
  return facts;
}
