// Moteur statistique « poisson-1.1 » (référence des backtests ; la production utilise poisson-2.0).
//
// Modèle de Poisson indépendant (type Maher / Dixon-Coles sans correction) :
//   λ domicile  = moyenne_buts_domicile_ligue × attaque_dom(équipe A) × défense_ext(équipe B)
//   λ extérieur = moyenne_buts_extérieur_ligue × attaque_ext(équipe B) × défense_dom(équipe A)
// Chaque force est « rétrécie » vers 1 (la moyenne de la ligue) avec k matchs fictifs :
// une équipe qui a joué 2 matchs pèse peu, une équipe qui en a joué 15 pèse beaucoup.
// Seuls les matchs joués AVANT le coup d'envoi sont utilisés (aucune fuite du futur).
// v1.1 : la saison précédente de la compétition compte aussi, avec un poids réduit, pour ne
// pas ramener toutes les équipes à la moyenne en début de saison.
// Fonctions pures, sans accès réseau : testables et rejouables sur l'historique.

/** Version du moteur en production (modèle : poisson2.ts, activé le 31/10 après backtest). */
/** Moteur de production (LOT 28 : poisson-3.0, compétitions reliées et niveau des championnats). */
export const ENGINE_VERSION = "poisson-3.0";
/** Ancien moteur (forces calculées dans la seule compétition), gardé pour comparaison. */
export const ENGINE_VERSION_2 = "poisson-2.0";

export interface PlayedMatch {
  kickoffAt: string;
  homeId: number;
  awayId: number;
  homeGoals: number;
  awayGoals: number;
  /** Poids dans le modèle (1 par défaut ; saison précédente : PRIOR_SEASON_WEIGHT). */
  weight?: number;
}

/** Poids des matchs de la saison précédente (même compétition) dans les forces des équipes. */
export const PRIOR_SEASON_WEIGHT = 0.5;

/** Matchs de la saison précédente, pondérés, à ajouter à l'historique du modèle. */
export function weighted(matches: PlayedMatch[], weight: number): PlayedMatch[] {
  return matches.map((m) => ({ ...m, weight }));
}

export interface SideRecord {
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
}

export interface ModelOptions {
  /** Matchs fictifs « à la moyenne » ajoutés à chaque équipe (rétrécissement). */
  shrinkK: number;
  /** Matchs fictifs ajoutés à la ligue, avec les moyennes a priori ci-dessous. */
  leaguePriorMatches: number;
  priorHomeGoals: number;
  priorAwayGoals: number;
  maxGoals: number;
}

export const DEFAULT_OPTIONS: ModelOptions = {
  shrinkK: 5,
  leaguePriorMatches: 20,
  priorHomeGoals: 1.5,
  priorAwayGoals: 1.2,
  maxGoals: 10,
};

export type Reliability = "faible" | "moyenne" | "bonne";

export interface ModelResult {
  lambdaHome: number;
  lambdaAway: number;
  leagueHomeAvg: number;
  leagueAwayAvg: number;
  sample: { leagueMatches: number; homeTeamHomeMatches: number; awayTeamAwayMatches: number };
  reliability: Reliability;
  probabilities: Record<string, number>;
  topScores: { score: string; probability: number }[];
}

export const GOAL_LINES = [0.5, 1.5, 2.5, 3.5];

function emptyRecord(): SideRecord {
  return { played: 0, won: 0, drawn: 0, lost: 0, goalsFor: 0, goalsAgainst: 0 };
}

function addResult(r: SideRecord, gf: number, ga: number): void {
  r.played++;
  r.goalsFor += gf;
  r.goalsAgainst += ga;
  if (gf > ga) r.won++;
  else if (gf === ga) r.drawn++;
  else r.lost++;
}

/** Bilan d'une équipe à domicile ou à l'extérieur sur un ensemble de matchs. */
export function sideRecord(history: PlayedMatch[], teamId: number, side: "home" | "away" | "all"): SideRecord {
  const r = emptyRecord();
  for (const m of history) {
    if ((side === "home" || side === "all") && m.homeId === teamId) addResult(r, m.homeGoals, m.awayGoals);
    if ((side === "away" || side === "all") && m.awayId === teamId) addResult(r, m.awayGoals, m.homeGoals);
  }
  return r;
}

export function reliabilityFor(homeTeamHomeMatches: number, awayTeamAwayMatches: number): Reliability {
  const n = Math.min(homeTeamHomeMatches, awayTeamAwayMatches);
  if (n < 4) return "faible";
  if (n < 8) return "moyenne";
  return "bonne";
}

const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x));
export const round = (x: number, digits = 3) => {
  const f = 10 ** digits;
  return Math.round(x * f) / f;
};

/** λ domicile et extérieur à partir de l'historique (même compétition, même saison, avant le match). */
export function expectedGoals(
  history: PlayedMatch[],
  homeId: number,
  awayId: number,
  options: ModelOptions = DEFAULT_OPTIONS,
) {
  let n = 0;
  let sumHome = 0;
  let sumAway = 0;
  const homeAtHome = { played: 0, goalsFor: 0, goalsAgainst: 0 };
  const awayAway = { played: 0, goalsFor: 0, goalsAgainst: 0 };
  for (const m of history) {
    const w = m.weight ?? 1;
    n += w;
    sumHome += w * m.homeGoals;
    sumAway += w * m.awayGoals;
    if (m.homeId === homeId) {
      homeAtHome.played += w;
      homeAtHome.goalsFor += w * m.homeGoals;
      homeAtHome.goalsAgainst += w * m.awayGoals;
    }
    if (m.awayId === awayId) {
      awayAway.played += w;
      awayAway.goalsFor += w * m.awayGoals;
      awayAway.goalsAgainst += w * m.homeGoals;
    }
  }
  const p = options.leaguePriorMatches;
  const leagueHome = (sumHome + p * options.priorHomeGoals) / (n + p);
  const leagueAway = (sumAway + p * options.priorAwayGoals) / (n + p);
  const k = options.shrinkK;
  // Forces relatives (1 = moyenne de la ligue), rétrécies vers 1.
  const attackHome = (homeAtHome.goalsFor + k * leagueHome) / (homeAtHome.played + k) / leagueHome;
  const defenseHome = (homeAtHome.goalsAgainst + k * leagueAway) / (homeAtHome.played + k) / leagueAway;
  const attackAway = (awayAway.goalsFor + k * leagueAway) / (awayAway.played + k) / leagueAway;
  const defenseAway = (awayAway.goalsAgainst + k * leagueHome) / (awayAway.played + k) / leagueHome;

  return {
    lambdaHome: clamp(leagueHome * attackHome * defenseAway, 0.1, 5),
    lambdaAway: clamp(leagueAway * attackAway * defenseHome, 0.1, 5),
    leagueHome,
    leagueAway,
    leagueMatches: Math.round(n * 10) / 10,
    homeTeamHomeMatches: Math.round(homeAtHome.played * 10) / 10,
    awayTeamAwayMatches: Math.round(awayAway.played * 10) / 10,
  };
}

function poissonPmf(lambda: number, max: number): number[] {
  const out = [Math.exp(-lambda)];
  for (let i = 1; i <= max; i++) out.push(out[i - 1] * lambda / i);
  return out;
}

/** Matrice des scores exacts [buts domicile][buts extérieur], normalisée (somme = 1). */
export function scoreMatrix(lambdaHome: number, lambdaAway: number, maxGoals = 10): number[][] {
  const ph = poissonPmf(lambdaHome, maxGoals);
  const pa = poissonPmf(lambdaAway, maxGoals);
  let total = 0;
  const m = ph.map((h) => pa.map((a) => {
    total += h * a;
    return h * a;
  }));
  return m.map((row) => row.map((v) => v / total));
}

export function outcomeKey(market: string, outcome: string, line: number | null): string {
  return line === null ? `${market}.${outcome}` : `${market}.${outcome}.${line}`;
}

/** Lignes des buts par équipe (marchés TTH et TTA). */
export const TEAM_GOAL_LINES = [0.5, 1.5, 2.5];

/**
 * Probabilités des marchés suivis : 1X2, double chance, plus/moins, les deux marquent,
 * remboursé si nul (DNB, probabilité sachant qu'il n'y a pas match nul) et buts de chaque
 * équipe (TTH domicile, TTA extérieur).
 */
export function marketProbabilities(matrix: number[][]): Record<string, number> {
  let home = 0, draw = 0, away = 0, btts = 0;
  const totals = new Map<number, number>();
  const homeGoals = new Map<number, number>();
  const awayGoals = new Map<number, number>();
  matrix.forEach((row, h) =>
    row.forEach((p, a) => {
      if (h > a) home += p;
      else if (h === a) draw += p;
      else away += p;
      if (h > 0 && a > 0) btts += p;
      totals.set(h + a, (totals.get(h + a) ?? 0) + p);
      homeGoals.set(h, (homeGoals.get(h) ?? 0) + p);
      awayGoals.set(a, (awayGoals.get(a) ?? 0) + p);
    })
  );
  const probs: Record<string, number> = {
    "1X2.HOME": home,
    "1X2.DRAW": draw,
    "1X2.AWAY": away,
    "DC.1X": home + draw,
    "DC.12": home + away,
    "DC.X2": draw + away,
    "BTTS.YES": btts,
    "BTTS.NO": 1 - btts,
  };
  for (const line of GOAL_LINES) {
    let under = 0;
    for (const [goals, p] of totals) if (goals < line) under += p;
    probs[outcomeKey("OU", "OVER", line)] = 1 - under;
    probs[outcomeKey("OU", "UNDER", line)] = under;
  }
  if (home + away > 0) {
    probs["DNB.HOME"] = home / (home + away);
    probs["DNB.AWAY"] = away / (home + away);
  }
  for (const [market, dist] of [["TTH", homeGoals], ["TTA", awayGoals]] as const) {
    for (const line of TEAM_GOAL_LINES) {
      let under = 0;
      for (const [goals, p] of dist) if (goals < line) under += p;
      probs[outcomeKey(market, "OVER", line)] = 1 - under;
      probs[outcomeKey(market, "UNDER", line)] = under;
    }
  }
  for (const key of Object.keys(probs)) probs[key] = round(clamp(probs[key], 0, 1));
  return probs;
}

export function topScores(matrix: number[][], count = 3) {
  const all: { score: string; probability: number }[] = [];
  matrix.forEach((row, h) => row.forEach((p, a) => all.push({ score: `${h}-${a}`, probability: p })));
  return all.sort((x, y) => y.probability - x.probability).slice(0, count)
    .map((s) => ({ score: s.score, probability: round(s.probability) }));
}

/** Modèle complet pour un match, à partir de l'historique antérieur à son coup d'envoi. */
export function runModel(
  history: PlayedMatch[],
  homeId: number,
  awayId: number,
  options: ModelOptions = DEFAULT_OPTIONS,
): ModelResult {
  const xg = expectedGoals(history, homeId, awayId, options);
  const matrix = scoreMatrix(xg.lambdaHome, xg.lambdaAway, options.maxGoals);
  return {
    lambdaHome: round(xg.lambdaHome, 2),
    lambdaAway: round(xg.lambdaAway, 2),
    leagueHomeAvg: round(xg.leagueHome, 2),
    leagueAwayAvg: round(xg.leagueAway, 2),
    sample: {
      leagueMatches: xg.leagueMatches,
      homeTeamHomeMatches: xg.homeTeamHomeMatches,
      awayTeamAwayMatches: xg.awayTeamAwayMatches,
    },
    reliability: reliabilityFor(xg.homeTeamHomeMatches, xg.awayTeamAwayMatches),
    probabilities: marketProbabilities(matrix),
    topScores: topScores(matrix),
  };
}

export interface TableRow {
  teamId: number;
  rank: number;
  played: number;
  points: number;
  goalDiff: number;
  goalsFor: number;
}

/** Classement recalculé à une date donnée (victoire 3 pts, nul 1 pt). */
export function tableAt(history: PlayedMatch[]): TableRow[] {
  const rows = new Map<number, Omit<TableRow, "rank">>();
  const get = (id: number) => {
    let r = rows.get(id);
    if (!r) {
      r = { teamId: id, played: 0, points: 0, goalDiff: 0, goalsFor: 0 };
      rows.set(id, r);
    }
    return r;
  };
  for (const m of history) {
    const h = get(m.homeId);
    const a = get(m.awayId);
    h.played++;
    a.played++;
    h.goalsFor += m.homeGoals;
    a.goalsFor += m.awayGoals;
    h.goalDiff += m.homeGoals - m.awayGoals;
    a.goalDiff += m.awayGoals - m.homeGoals;
    if (m.homeGoals > m.awayGoals) h.points += 3;
    else if (m.homeGoals < m.awayGoals) a.points += 3;
    else {
      h.points++;
      a.points++;
    }
  }
  return [...rows.values()]
    .sort((x, y) => y.points - x.points || y.goalDiff - x.goalDiff || y.goalsFor - x.goalsFor)
    .map((r, i) => ({ ...r, rank: i + 1 }));
}
