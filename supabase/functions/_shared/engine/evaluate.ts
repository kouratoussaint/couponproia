// Évaluation du moteur sur l'historique (backtest « marche avant ») : chaque match est
// prédit uniquement avec les matchs joués avant lui, puis comparé au résultat réel.
// Modèle évalué : celui de production (poisson-2.0, forces calculées la veille du match).
// Référence (baseline) : fréquences observées jusque-là dans la compétition
// (1 / N / 2, plus de 2,5 buts, les deux marquent), avec lissage de Laplace.
// Plus le score de Brier et la perte logarithmique sont BAS, meilleur est le modèle.
import { ENGINE_VERSION, type PlayedMatch, round } from "./poisson.ts";
import { DEFAULT_OPTIONS_2, fitStrengths, runModel2FromStrengths, type Strengths } from "./poisson2.ts";
import { ENGINE_VERSION_3, LeagueModel, type Match3, runModel3, type Strengths3 } from "./poisson3.ts";

export interface EvaluationOptions {
  /** Matchs déjà joués dans la compétition avant de commencer à noter. */
  warmupMatches: number;
}

export interface CalibrationBin {
  from: number;
  to: number;
  count: number;
  predicted: number;
  observed: number;
}

export interface Scores {
  matches: number;
  brierModel: number;
  brierBaseline: number;
  loglossModel: number;
  loglossBaseline: number;
  accuracyModel: number;
  accuracyBaseline: number;
}

export interface Evaluation {
  engineVersion: string;
  oneXTwo: Scores;
  over25: Omit<Scores, "accuracyModel" | "accuracyBaseline"> & { accuracyModel: number };
  btts: Omit<Scores, "accuracyModel" | "accuracyBaseline"> & { accuracyModel: number };
  /** Remboursé si nul : matchs sans nul seulement (victoire domicile ou extérieur). */
  dnb: Omit<Scores, "accuracyModel" | "accuracyBaseline"> & { accuracyModel: number };
  /** Buts par équipe : domicile plus de 1,5 et extérieur plus de 0,5 (lignes les plus cotées). */
  teamTotals: Omit<Scores, "accuracyModel" | "accuracyBaseline"> & { accuracyModel: number };
  calibration: CalibrationBin[];
}

const EPS = 1e-12;
const ll = (p: number) => -Math.log(Math.max(p, EPS));

class Acc {
  n = 0;
  brierM = 0;
  brierB = 0;
  llM = 0;
  llB = 0;
  hitM = 0;
  hitB = 0;
  add(model: number[], base: number[], outcome: number) {
    this.n++;
    model.forEach((p, i) => this.brierM += (p - (i === outcome ? 1 : 0)) ** 2);
    base.forEach((p, i) => this.brierB += (p - (i === outcome ? 1 : 0)) ** 2);
    this.llM += ll(model[outcome]);
    this.llB += ll(base[outcome]);
    if (argmax(model) === outcome) this.hitM++;
    if (argmax(base) === outcome) this.hitB++;
  }
  scores(): Scores {
    const d = Math.max(this.n, 1);
    return {
      matches: this.n,
      brierModel: round(this.brierM / d, 5),
      brierBaseline: round(this.brierB / d, 5),
      loglossModel: round(this.llM / d, 5),
      loglossBaseline: round(this.llB / d, 5),
      accuracyModel: round(this.hitM / d, 4),
      accuracyBaseline: round(this.hitB / d, 4),
    };
  }
}

function argmax(xs: number[]): number {
  return xs.reduce((best, x, i) => (x > xs[best] ? i : best), 0);
}

/** Évalue une compétition-saison. `matches` : matchs terminés, dans n'importe quel ordre. */
export function evaluateCompetition(
  matches: PlayedMatch[],
  options: EvaluationOptions = { warmupMatches: 30 },
  bins: number[][] = Array.from({ length: 10 }, () => [0, 0, 0]),
  /** Saison précédente, déjà pondérée : connue avant chaque match évalué. */
  prior: PlayedMatch[] = [],
) {
  const sorted = [...matches].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));
  const { r1x2, rOver, rBtts, rDnb, rTeam } = newAccs();
  const counts = newCounts();

  // Forces calculées une fois par jour de match, avec les seuls matchs des jours précédents
  // (prudent : aucun match du jour même n'est utilisé) ; limite le temps de calcul.
  const priorAll = prior.map((p) => ({ ...p, weight: 1 }));
  const byDay = new Map<string, Strengths>();
  for (let i = 0; i < sorted.length; i++) {
    const m = sorted[i];
    // Matchs strictement antérieurs (deux matchs simultanés ne se « voient » pas).
    let j = i;
    while (j > 0 && sorted[j - 1].kickoffAt === m.kickoffAt) j--;
    const history = sorted.slice(0, j);

    if (history.length >= options.warmupMatches) {
      const day = m.kickoffAt.slice(0, 10);
      let s = byDay.get(day);
      if (!s) {
        const before = [...priorAll, ...history.filter((h) => h.kickoffAt.slice(0, 10) < day)].map((h) => ({ ...h, weight: 1 }));
        s = fitStrengths(before, Date.parse(`${day}T00:00:00Z`), DEFAULT_OPTIONS_2);
        byDay.set(day, s);
      }
      const p = runModel2FromStrengths(s, m.homeId, m.awayId, DEFAULT_OPTIONS_2).probabilities;
      scoreMatch(m, p, counts, history.length, { r1x2, rOver, rBtts, rDnb, rTeam }, bins);
    }

    countMatch(m, counts);
  }
  return { r1x2, rOver, rBtts, rDnb, rTeam, bins };
}

type Counts = { home: number; draw: number; away: number; over: number; btts: number; home15: number; away05: number };
interface Accs {
  r1x2: Acc;
  rOver: Acc;
  rBtts: Acc;
  rDnb: Acc;
  rTeam: Acc;
}
const newCounts = (): Counts => ({ home: 0, draw: 0, away: 0, over: 0, btts: 0, home15: 0, away05: 0 });
const newAccs = (): Accs => ({ r1x2: new Acc(), rOver: new Acc(), rBtts: new Acc(), rDnb: new Acc(), rTeam: new Acc() });

function countMatch(m: PlayedMatch, counts: Counts) {
  if (m.homeGoals > m.awayGoals) counts.home++;
  else if (m.homeGoals === m.awayGoals) counts.draw++;
  else counts.away++;
  if (m.homeGoals + m.awayGoals > 2.5) counts.over++;
  if (m.homeGoals > 0 && m.awayGoals > 0) counts.btts++;
  if (m.homeGoals > 1.5) counts.home15++;
  if (m.awayGoals > 0.5) counts.away05++;
}

/** Note un match : probabilités du modèle contre la référence (fréquences des `n` matchs d'avant). */
function scoreMatch(m: PlayedMatch, p: Record<string, number>, counts: Counts, n: number, a: Accs, bins: number[][]) {
  const base1x2 = [(counts.home + 1) / (n + 3), (counts.draw + 1) / (n + 3), (counts.away + 1) / (n + 3)];
  const outcome = m.homeGoals > m.awayGoals ? 0 : m.homeGoals === m.awayGoals ? 1 : 2;
  const model1x2 = [p["1X2.HOME"], p["1X2.DRAW"], p["1X2.AWAY"]];
  a.r1x2.add(model1x2, base1x2, outcome);

  const over = m.homeGoals + m.awayGoals > 2.5 ? 0 : 1;
  const baseOver = (counts.over + 1) / (n + 2);
  a.rOver.add([p["OU.OVER.2.5"], 1 - p["OU.OVER.2.5"]], [baseOver, 1 - baseOver], over);

  const btts = m.homeGoals > 0 && m.awayGoals > 0 ? 0 : 1;
  const baseBtts = (counts.btts + 1) / (n + 2);
  a.rBtts.add([p["BTTS.YES"], 1 - p["BTTS.YES"]], [baseBtts, 1 - baseBtts], btts);

  if (m.homeGoals !== m.awayGoals) {
    const baseDnb = (counts.home + 1) / (counts.home + counts.away + 2);
    a.rDnb.add([p["DNB.HOME"], 1 - p["DNB.HOME"]], [baseDnb, 1 - baseDnb], m.homeGoals > m.awayGoals ? 0 : 1);
  }
  const baseH15 = (counts.home15 + 1) / (n + 2);
  a.rTeam.add([p["TTH.OVER.1.5"], 1 - p["TTH.OVER.1.5"]], [baseH15, 1 - baseH15], m.homeGoals > 1.5 ? 0 : 1);
  const baseA05 = (counts.away05 + 1) / (n + 2);
  a.rTeam.add([p["TTA.OVER.0.5"], 1 - p["TTA.OVER.0.5"]], [baseA05, 1 - baseA05], m.awayGoals > 0.5 ? 0 : 1);

  model1x2.forEach((prob, k) => {
    const b = Math.min(9, Math.floor(prob * 10));
    bins[b][0]++;
    bins[b][1] += prob;
    bins[b][2] += k === outcome ? 1 : 0;
  });
}

function merge(target: Acc, src: Acc) {
  target.n += src.n;
  target.brierM += src.brierM;
  target.brierB += src.brierB;
  target.llM += src.llM;
  target.llB += src.llB;
  target.hitM += src.hitM;
  target.hitB += src.hitB;
}

/** Évaluation globale de plusieurs compétitions, avec le détail par compétition. */
export function evaluate(
  groups: { name: string; matches: PlayedMatch[]; prior?: PlayedMatch[] }[],
  options: EvaluationOptions = { warmupMatches: 30 },
) {
  const all1x2 = new Acc();
  const allOver = new Acc();
  const allBtts = new Acc();
  const allDnb = new Acc();
  const allTeam = new Acc();
  const bins: number[][] = Array.from({ length: 10 }, () => [0, 0, 0]);
  const perCompetition: Record<string, Scores> = {};

  for (const g of groups) {
    const r = evaluateCompetition(g.matches, options, bins, g.prior ?? []);
    merge(all1x2, r.r1x2);
    merge(allOver, r.rOver);
    merge(allBtts, r.rBtts);
    merge(allDnb, r.rDnb);
    merge(allTeam, r.rTeam);
    if (r.r1x2.n > 0) perCompetition[g.name] = r.r1x2.scores();
  }
  return report(ENGINE_VERSION, { r1x2: all1x2, rOver: allOver, rBtts: allBtts, rDnb: allDnb, rTeam: allTeam }, bins, perCompetition);
}

function report(engineVersion: string, all: Accs, bins: number[][], perCompetition: Record<string, Scores>) {
  const { r1x2: all1x2, rOver: allOver, rBtts: allBtts, rDnb: allDnb, rTeam: allTeam } = all;

  const strip = (s: Scores) => {
    const { accuracyBaseline: _ignored, ...rest } = s;
    return rest;
  };
  const evaluation: Evaluation = {
    engineVersion,
    oneXTwo: all1x2.scores(),
    over25: strip(allOver.scores()),
    btts: strip(allBtts.scores()),
    dnb: strip(allDnb.scores()),
    teamTotals: strip(allTeam.scores()),
    calibration: bins.map(([count, sumP, hits], i) => ({
      from: i / 10,
      to: (i + 1) / 10,
      count,
      predicted: count ? round(sumP / count, 3) : 0,
      observed: count ? round(hits / count, 3) : 0,
    })).filter((b) => b.count > 0),
  };
  return { evaluation, perCompetition };
}

/**
 * Évaluation officielle de poisson-3.0 : mêmes matchs notés et même référence que poisson-2.0
 * (par compétition-saison, après 30 matchs), mais chaque match est prédit avec les forces
 * « reliées » calculées la veille sur TOUS les matchs connus (`all`, toutes compétitions).
 * Un seul calcul par jour, repris de la veille (quelques itérations suffisent).
 */
export function evaluate3(
  groups: { name: string; competitionId: number; matches: PlayedMatch[] }[],
  all: Match3[],
  leagues: Set<number>,
  options: EvaluationOptions = { warmupMatches: 30 },
) {
  type Point = { day: string; m: PlayedMatch; competitionId: number; group: string; counts: Counts; n: number };
  const points: Point[] = [];
  for (const g of groups) {
    const sorted = [...g.matches].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));
    const counts = newCounts();
    for (let i = 0; i < sorted.length; i++) {
      const m = sorted[i];
      let j = i;
      while (j > 0 && sorted[j - 1].kickoffAt === m.kickoffAt) j--;
      if (j >= options.warmupMatches) {
        points.push({ day: m.kickoffAt.slice(0, 10), m, competitionId: g.competitionId, group: g.name, counts: { ...counts }, n: j });
      }
      countMatch(m, counts);
    }
  }
  points.sort((a, b) => a.day.localeCompare(b.day));

  const history = [...all].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));
  const model = new LeagueModel(leagues);
  const total = newAccs();
  const perGroup = new Map<string, Accs>();
  const bins: number[][] = Array.from({ length: 10 }, () => [0, 0, 0]);
  let cut = 0, day = "", s: Strengths3 | null = null;
  for (const pt of points) {
    if (pt.day !== day) {
      day = pt.day;
      const at = Date.parse(`${day}T00:00:00Z`);
      while (cut < history.length && Date.parse(history[cut].kickoffAt) < at) model.add({ ...history[cut++], weight: 1 });
      s = model.solve(at);
    }
    const p = runModel3(s!, pt.competitionId, pt.m.homeId, pt.m.awayId).probabilities;
    const g = perGroup.get(pt.group) ?? perGroup.set(pt.group, newAccs()).get(pt.group)!;
    scoreMatch(pt.m, p, pt.counts, pt.n, g, bins);
    scoreMatch(pt.m, p, pt.counts, pt.n, total, Array.from({ length: 10 }, () => [0, 0, 0]));
  }
  const perCompetition: Record<string, Scores> = {};
  for (const [name, a] of perGroup) if (a.r1x2.n > 0) perCompetition[name] = a.r1x2.scores();
  return report(ENGINE_VERSION_3, total, bins, perCompetition);
}
