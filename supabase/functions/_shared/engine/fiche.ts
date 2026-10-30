// Fiche d'analyse : tout ce que le moteur sait d'un match, calculé à partir de
// données réelles antérieures au coup d'envoi. C'est la SEULE source que l'IA a le
// droit d'utiliser ; l'application l'affiche aussi telle quelle (transparence).
import {
  ENGINE_VERSION,
  GOAL_LINES,
  outcomeKey,
  type PlayedMatch,
  round,
  runModel,
  sideRecord,
  type SideRecord,
  tableAt,
} from "./poisson.ts";

export interface NamedMatch extends PlayedMatch {
  homeName: string;
  awayName: string;
  competitionName?: string;
}

export interface OddsRow {
  market_code: string;
  outcome_code: string;
  line: number | null;
  odd_median: number;
  odd_best: number;
  bookmakers_count: number;
  captured_at: string;
}

export interface FicheInput {
  match: {
    id: number;
    kickoffAt: string;
    season: number;
    round: string | null;
    competition: { id: number; name: string; type: string | null };
    home: { id: number; name: string };
    away: { id: number; name: string };
  };
  /** Même compétition, même saison, matchs terminés AVANT le coup d'envoi. */
  history: PlayedMatch[];
  /** Derniers matchs terminés de chaque équipe (toutes compétitions), du plus récent au plus ancien. */
  recentHome: NamedMatch[];
  recentAway: NamedMatch[];
  headToHead: NamedMatch[];
  odds: OddsRow[];
  generatedAt: string;
}

export interface OddsLineFiche {
  key: string;
  odd_median: number;
  odd_best: number;
  bookmakers: number;
  implied_probability: number | null;
  model_probability: number | null;
  edge: number | null;
}

export type Fiche = ReturnType<typeof buildFiche>;

function recordJson(r: SideRecord) {
  return {
    played: r.played,
    won: r.won,
    drawn: r.drawn,
    lost: r.lost,
    goals_for: r.goalsFor,
    goals_against: r.goalsAgainst,
  };
}

/** Forme : V (victoire), N (nul), D (défaite), du plus récent au plus ancien. */
export function formOf(matches: PlayedMatch[], teamId: number, count = 5): string {
  return matches.slice(0, count).map((m) => {
    const gf = m.homeId === teamId ? m.homeGoals : m.awayGoals;
    const ga = m.homeId === teamId ? m.awayGoals : m.homeGoals;
    return gf > ga ? "V" : gf === ga ? "N" : "D";
  }).join("");
}

function groupOf(row: OddsRow): string {
  return row.line === null ? row.market_code : `${row.market_code}.${row.line}`;
}

/**
 * Probabilités implicites des cotes, marge du bookmaker retirée : dans chaque groupe
 * complet (1/X/2, plus/moins d'une ligne…), les inverses des cotes médianes sont
 * ramenés à une somme de 1 (2 pour la double chance, dont les issues se recouvrent).
 */
export function impliedProbabilities(odds: OddsRow[]): Map<string, number> {
  const size: Record<string, number> = { "1X2": 3, DC: 3, OU: 2, BTTS: 2 };
  const groups = new Map<string, OddsRow[]>();
  for (const o of odds) {
    const g = groupOf(o);
    groups.set(g, [...(groups.get(g) ?? []), o]);
  }
  const out = new Map<string, number>();
  for (const rows of groups.values()) {
    const market = rows[0].market_code;
    if (rows.length !== size[market]) continue;
    const target = market === "DC" ? 2 : 1;
    const sum = rows.reduce((s, r) => s + 1 / r.odd_median, 0);
    for (const r of rows) {
      out.set(outcomeKey(r.market_code, r.outcome_code, r.line), round((1 / r.odd_median) / sum * target));
    }
  }
  return out;
}

function h2hJson(m: NamedMatch) {
  return {
    date: m.kickoffAt.slice(0, 10),
    competition: m.competitionName ?? null,
    home: m.homeName,
    away: m.awayName,
    score: `${m.homeGoals}-${m.awayGoals}`,
  };
}

export function buildFiche(input: FicheInput) {
  const { match } = input;
  const model = runModel(input.history, match.home.id, match.away.id);

  const implied = impliedProbabilities(input.odds);
  const oddsLines: OddsLineFiche[] = input.odds.map((o) => {
    const key = outcomeKey(o.market_code, o.outcome_code, o.line);
    const modelP = model.probabilities[key] ?? null;
    const impliedP = implied.get(key) ?? null;
    return {
      key,
      odd_median: Number(o.odd_median),
      odd_best: Number(o.odd_best),
      bookmakers: o.bookmakers_count,
      implied_probability: impliedP,
      model_probability: modelP,
      edge: modelP !== null && impliedP !== null ? round(modelP - impliedP) : null,
    };
  });
  const capturedAt = input.odds.map((o) => o.captured_at).sort().at(-1) ?? null;

  const isLeague = match.competition.type === "league";
  const table = isLeague && input.history.length > 0 ? tableAt(input.history) : [];
  const rowOf = (id: number) => {
    const r = table.find((t) => t.teamId === id);
    return r ? { rank: r.rank, points: r.points, played: r.played, goal_diff: r.goalDiff } : null;
  };

  const missing: string[] = [
    "Compositions, blessures et suspensions : non fournies par la source de données",
  ];
  if (input.odds.length === 0) missing.push("Cotes du marché indisponibles pour ce match");
  if (model.reliability === "faible") {
    missing.push("Peu de matchs joués cette saison par ces équipes : estimation fragile");
  }
  if (input.history.length < 20) missing.push("Début de saison : moyennes de la compétition encore peu stables");
  if (input.headToHead.length === 0) missing.push("Aucune confrontation directe dans les données disponibles");

  return {
    engine_version: ENGINE_VERSION,
    generated_at: input.generatedAt,
    note: "Probabilités estimées par un modèle statistique (Poisson) : ce sont des estimations, pas des certitudes.",
    match: {
      id: match.id,
      competition: match.competition.name,
      season: match.season,
      round: match.round,
      kickoff_at: match.kickoffAt,
      home: match.home.name,
      away: match.away.name,
    },
    sample: {
      competition_matches: model.sample.leagueMatches,
      home_team_home_matches: model.sample.homeTeamHomeMatches,
      away_team_away_matches: model.sample.awayTeamAwayMatches,
    },
    reliability: model.reliability,
    model: {
      expected_goals_home: model.lambdaHome,
      expected_goals_away: model.lambdaAway,
      competition_avg_goals_home: model.leagueHomeAvg,
      competition_avg_goals_away: model.leagueAwayAvg,
      probabilities: model.probabilities,
      top_scores: model.topScores,
    },
    teams: {
      home: {
        name: match.home.name,
        form: formOf(input.recentHome, match.home.id),
        at_home_this_season: recordJson(sideRecord(input.history, match.home.id, "home")),
        this_season: recordJson(sideRecord(input.history, match.home.id, "all")),
        standing: rowOf(match.home.id),
      },
      away: {
        name: match.away.name,
        form: formOf(input.recentAway, match.away.id),
        away_this_season: recordJson(sideRecord(input.history, match.away.id, "away")),
        this_season: recordJson(sideRecord(input.history, match.away.id, "all")),
        standing: rowOf(match.away.id),
      },
    },
    head_to_head: input.headToHead.slice(0, 5).map(h2hJson),
    market: {
      available: oddsLines.length > 0,
      captured_at: capturedAt,
      lines: oddsLines,
    },
    goal_lines: GOAL_LINES,
    missing,
  };
}
