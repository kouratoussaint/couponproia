// Évaluation du moteur sur l'historique (backtest « marche avant ») : chaque match est
// prédit uniquement avec les matchs joués avant lui, puis comparé au résultat réel.
// Référence (baseline) : fréquences observées jusque-là dans la compétition
// (1 / N / 2, plus de 2,5 buts, les deux marquent), avec lissage de Laplace.
// Plus le score de Brier et la perte logarithmique sont BAS, meilleur est le modèle.
import { ENGINE_VERSION, type PlayedMatch, round, runModel } from "./poisson.ts";

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
  const r1x2 = new Acc();
  const rOver = new Acc();
  const rBtts = new Acc();
  const counts = { home: 0, draw: 0, away: 0, over: 0, btts: 0 };

  for (let i = 0; i < sorted.length; i++) {
    const m = sorted[i];
    // Matchs strictement antérieurs (deux matchs simultanés ne se « voient » pas).
    let j = i;
    while (j > 0 && sorted[j - 1].kickoffAt === m.kickoffAt) j--;
    const history = sorted.slice(0, j);

    if (history.length >= options.warmupMatches) {
      const p = runModel(prior.length ? [...prior, ...history] : history, m.homeId, m.awayId).probabilities;
      const n = history.length;
      const base1x2 = [(counts.home + 1) / (n + 3), (counts.draw + 1) / (n + 3), (counts.away + 1) / (n + 3)];
      const outcome = m.homeGoals > m.awayGoals ? 0 : m.homeGoals === m.awayGoals ? 1 : 2;
      const model1x2 = [p["1X2.HOME"], p["1X2.DRAW"], p["1X2.AWAY"]];
      r1x2.add(model1x2, base1x2, outcome);

      const over = m.homeGoals + m.awayGoals > 2.5 ? 0 : 1;
      const baseOver = (counts.over + 1) / (n + 2);
      rOver.add([p["OU.OVER.2.5"], 1 - p["OU.OVER.2.5"]], [baseOver, 1 - baseOver], over);

      const btts = m.homeGoals > 0 && m.awayGoals > 0 ? 0 : 1;
      const baseBtts = (counts.btts + 1) / (n + 2);
      rBtts.add([p["BTTS.YES"], 1 - p["BTTS.YES"]], [baseBtts, 1 - baseBtts], btts);

      model1x2.forEach((prob, k) => {
        const b = Math.min(9, Math.floor(prob * 10));
        bins[b][0]++;
        bins[b][1] += prob;
        bins[b][2] += k === outcome ? 1 : 0;
      });
    }

    if (m.homeGoals > m.awayGoals) counts.home++;
    else if (m.homeGoals === m.awayGoals) counts.draw++;
    else counts.away++;
    if (m.homeGoals + m.awayGoals > 2.5) counts.over++;
    if (m.homeGoals > 0 && m.awayGoals > 0) counts.btts++;
  }
  return { r1x2, rOver, rBtts, bins };
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
  const bins: number[][] = Array.from({ length: 10 }, () => [0, 0, 0]);
  const perCompetition: Record<string, Scores> = {};

  for (const g of groups) {
    const r = evaluateCompetition(g.matches, options, bins, g.prior ?? []);
    merge(all1x2, r.r1x2);
    merge(allOver, r.rOver);
    merge(allBtts, r.rBtts);
    if (r.r1x2.n > 0) perCompetition[g.name] = r.r1x2.scores();
  }

  const strip = (s: Scores) => {
    const { accuracyBaseline: _ignored, ...rest } = s;
    return rest;
  };
  const evaluation: Evaluation = {
    engineVersion: ENGINE_VERSION,
    oneXTwo: all1x2.scores(),
    over25: strip(allOver.scores()),
    btts: strip(allBtts.scores()),
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
