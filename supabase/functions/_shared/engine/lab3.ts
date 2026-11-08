// Laboratoire — expérience « Moteur 3.0 » (08/11/2026). Rien ici n'est utilisé en production :
// le module n'est appelé que par le mode `experiment` d'engine-evaluate, qui n'écrit rien.
//
// Variantes comparées sur EXACTEMENT les mêmes matchs que l'évaluation officielle :
//  A  — poisson-2.0 (production) : forces calculées dans la seule compétition.
//  B  — compétitions reliées : forces de chaque équipe calculées sur TOUS ses matchs (championnat,
//       coupes d'Europe et d'Afrique…), avec la moyenne de buts et l'avantage du terrain propres
//       à la compétition du match. Mêmes réglages que A (demi-vie, rétrécissement ; anciennes
//       saisons au poids 1 comme en production, seule la décroissance dans le temps joue).
//  +cal — recalibrage 1X2 « marche avant » : p_k^T, nul multiplié par e^d, renormalisé ; T et d
//       ajustés au début de chaque mois sur les seules prédictions des mois précédents.
//  Marché — pour les matchs dont la cote 1X2 a été relevée avant le coup d'envoi : probabilités
//       du marché (marge retirée) et mélanges modèle / marché.
// Seuls les matchs joués AVANT le jour du match sont utilisés. Fonctions pures.
import { marketProbabilities, type PlayedMatch, round } from "./poisson.ts";
import { DEFAULT_OPTIONS_2, dixonColesMatrix, fitStrengths, type Model2Options, runModel2FromStrengths } from "./poisson2.ts";

const DAY = 86400_000;
const EPS = 1e-12;
const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x));

export interface LabMatch extends PlayedMatch {
  id: number;
  competitionId: number;
  season: number;
}

export interface LabGroup {
  key: string;
  competitionId: number;
  season: number;
  matches: LabMatch[];
  /** Saison précédente de la compétition, déjà pondérée (comme l'évaluation officielle). */
  prior: PlayedMatch[];
}

// ---------------------------------------------------------------- variante B : forces globales

export interface GlobalStrengths {
  homeAvg: Map<number, number>;
  awayAvg: Map<number, number>;
  attack: Map<number, number>;
  defense: Map<number, number>;
}

/**
 * Forces globales : chaque match compte dans sa compétition (moyennes domicile / extérieur de la
 * compétition) et pour les deux équipes, quelle que soit la compétition.
 */
export function fitGlobalStrengths(
  history: (PlayedMatch & { competitionId: number })[],
  at: number,
  o: Model2Options = DEFAULT_OPTIONS_2,
  weightOf: (m: PlayedMatch & { competitionId: number }) => number = (m) => m.weight ?? 1,
): GlobalStrengths {
  const n = history.length;
  const w = new Float64Array(n);
  const comp = new Map<number, { w: number; h: number; a: number }>();
  for (let r = 0; r < n; r++) {
    const m = history[r];
    const age = Math.max(0, (at - Date.parse(m.kickoffAt)) / DAY);
    w[r] = weightOf(m) * 0.5 ** (age / o.halfLifeDays);
    const c = comp.get(m.competitionId) ?? { w: 0, h: 0, a: 0 };
    c.w += w[r];
    c.h += w[r] * m.homeGoals;
    c.a += w[r] * m.awayGoals;
    comp.set(m.competitionId, c);
  }
  const p = o.leaguePriorMatches;
  const homeAvg = new Map<number, number>(), awayAvg = new Map<number, number>();
  for (const [id, c] of comp) {
    homeAvg.set(id, (c.h + p * o.priorHomeGoals) / (c.w + p));
    awayAvg.set(id, (c.a + p * o.priorAwayGoals) / (c.w + p));
  }
  const index = new Map<number, number>();
  const idx = (id: number) => {
    let i = index.get(id);
    if (i === undefined) index.set(id, i = index.size);
    return i;
  };
  const hi = new Int32Array(n), ai = new Int32Array(n);
  const bh = new Float64Array(n), ba = new Float64Array(n);
  let goals = 0, weightSum = 0;
  for (let r = 0; r < n; r++) {
    const m = history[r];
    hi[r] = idx(m.homeId);
    ai[r] = idx(m.awayId);
    bh[r] = homeAvg.get(m.competitionId)!;
    ba[r] = awayAvg.get(m.competitionId)!;
    goals += w[r] * (bh[r] + ba[r]);
    weightSum += w[r];
  }
  const k = o.shrinkK * (weightSum > 0 ? goals / weightSum / 2 : (o.priorHomeGoals + o.priorAwayGoals) / 2);
  const T = index.size;
  const att = new Float64Array(T).fill(1), def = new Float64Array(T).fill(1);
  const sc = new Float64Array(T), es = new Float64Array(T), co = new Float64Array(T), ec = new Float64Array(T);
  for (let it = 0; it < o.iterations; it++) {
    sc.fill(0);
    es.fill(0);
    co.fill(0);
    ec.fill(0);
    for (let r = 0; r < n; r++) {
      const h = hi[r], a = ai[r], x = w[r];
      const m = history[r];
      sc[h] += x * m.homeGoals;
      es[h] += x * bh[r] * def[a];
      sc[a] += x * m.awayGoals;
      es[a] += x * ba[r] * def[h];
      co[h] += x * m.awayGoals;
      ec[h] += x * ba[r] * att[a];
      co[a] += x * m.homeGoals;
      ec[a] += x * bh[r] * att[h];
    }
    for (let t = 0; t < T; t++) {
      att[t] = (sc[t] + k) / (es[t] + k);
      def[t] = (co[t] + k) / (ec[t] + k);
    }
  }
  const attack = new Map<number, number>(), defense = new Map<number, number>();
  for (const [id, t] of index) {
    attack.set(id, att[t]);
    defense.set(id, def[t]);
  }
  return { homeAvg, awayAvg, attack, defense };
}

/**
 * Variante C : comme B, plus un niveau par championnat national. Chaque équipe est rattachée
 * au championnat (type « league ») où elle a le plus joué ; ses forces sont relatives à ce
 * championnat (rétrécies vers 1 = la moyenne du championnat), et le niveau S du championnat
 * multiplie l'attaque et divise la défense. Dans un match de championnat, S s'annule ; il
 * n'est estimé que sur les matchs entre équipes de championnats différents (coupes
 * continentales), rétréci vers 1 avec `leagueShrink` buts fictifs. Une équipe sans
 * championnat suivi (sélections, clubs de championnats non suivis) garde S = 1. La prudence
 * (matchs fictifs) de chaque équipe suit le niveau de buts de ses propres matchs.
 */
export function fitLeagueStrengths(
  history: (PlayedMatch & { competitionId: number })[],
  at: number,
  leagues: Set<number>,
  o: Model2Options = DEFAULT_OPTIONS_2,
  weightOf: (m: PlayedMatch & { competitionId: number }) => number = (m) => m.weight ?? 1,
  leagueShrink = 10,
): GlobalStrengths & { leagueLevel: Map<number, number> } {
  const n = history.length;
  const w = new Float64Array(n);
  const comp = new Map<number, { w: number; h: number; a: number }>();
  const played = new Map<number, Map<number, number>>();
  for (let r = 0; r < n; r++) {
    const m = history[r];
    const age = Math.max(0, (at - Date.parse(m.kickoffAt)) / DAY);
    w[r] = weightOf(m) * 0.5 ** (age / o.halfLifeDays);
    const c = comp.get(m.competitionId) ?? { w: 0, h: 0, a: 0 };
    c.w += w[r];
    c.h += w[r] * m.homeGoals;
    c.a += w[r] * m.awayGoals;
    comp.set(m.competitionId, c);
    if (leagues.has(m.competitionId)) {
      for (const t of [m.homeId, m.awayId]) {
        const byComp = played.get(t) ?? played.set(t, new Map()).get(t)!;
        byComp.set(m.competitionId, (byComp.get(m.competitionId) ?? 0) + 1);
      }
    }
  }
  const p = o.leaguePriorMatches;
  const homeAvg = new Map<number, number>(), awayAvg = new Map<number, number>();
  for (const [id, c] of comp) {
    homeAvg.set(id, (c.h + p * o.priorHomeGoals) / (c.w + p));
    awayAvg.set(id, (c.a + p * o.priorAwayGoals) / (c.w + p));
  }
  // Championnat de rattachement (-1 : aucun championnat suivi).
  const leagueOfTeam = new Map<number, number>();
  for (const [t, byComp] of played) {
    let best = -1, most = 0;
    for (const [c, k] of byComp) if (k > most) [best, most] = [c, k];
    leagueOfTeam.set(t, best);
  }
  const index = new Map<number, number>();
  const idx = (id: number) => {
    let i = index.get(id);
    if (i === undefined) index.set(id, i = index.size);
    return i;
  };
  const leagueIndex = new Map<number, number>();
  const hi = new Int32Array(n), ai = new Int32Array(n), hl = new Int32Array(n), al = new Int32Array(n);
  const bh = new Float64Array(n), ba = new Float64Array(n);
  let goals = 0, weightSum = 0;
  const lidx = (team: number) => {
    const l = leagueOfTeam.get(team) ?? -1;
    if (l < 0) return -1;
    let i = leagueIndex.get(l);
    if (i === undefined) leagueIndex.set(l, i = leagueIndex.size);
    return i;
  };
  for (let r = 0; r < n; r++) {
    const m = history[r];
    hi[r] = idx(m.homeId);
    ai[r] = idx(m.awayId);
    hl[r] = lidx(m.homeId);
    al[r] = lidx(m.awayId);
    bh[r] = homeAvg.get(m.competitionId)!;
    ba[r] = awayAvg.get(m.competitionId)!;
    goals += w[r] * (bh[r] + ba[r]);
    weightSum += w[r];
  }
  // Prudence (matchs fictifs) propre à chaque équipe : niveau de buts de SES matchs. Une équipe
  // qui ne joue qu'une compétition retrouve exactement le réglage de poisson-2.0.
  const T = index.size, L = leagueIndex.size;
  const kw = new Float64Array(T), kg = new Float64Array(T);
  for (let r = 0; r < n; r++) {
    for (const t of [hi[r], ai[r]]) {
      kw[t] += w[r];
      kg[t] += w[r] * (bh[r] + ba[r]) / 2;
    }
  }
  const fallback = weightSum > 0 ? goals / weightSum / 2 : (o.priorHomeGoals + o.priorAwayGoals) / 2;
  const kOf = new Float64Array(T);
  for (let t = 0; t < T; t++) kOf[t] = o.shrinkK * (kw[t] > 0 ? kg[t] / kw[t] : fallback);
  const att = new Float64Array(T).fill(1), def = new Float64Array(T).fill(1);
  const lv = new Float64Array(L).fill(1);
  const S = (l: number) => (l < 0 ? 1 : lv[l]);
  const sc = new Float64Array(T), es = new Float64Array(T), co = new Float64Array(T), ec = new Float64Array(T);
  const lsc = new Float64Array(L), les = new Float64Array(L), lco = new Float64Array(L), lec = new Float64Array(L);
  for (let it = 0; it < o.iterations + 4; it++) {
    sc.fill(0);
    es.fill(0);
    co.fill(0);
    ec.fill(0);
    for (let r = 0; r < n; r++) {
      const h = hi[r], a = ai[r], x = w[r], m = history[r];
      const ratio = S(hl[r]) / S(al[r]); // 1 dans un match de championnat
      sc[h] += x * m.homeGoals;
      es[h] += x * bh[r] * ratio * def[a];
      sc[a] += x * m.awayGoals;
      es[a] += x * ba[r] / ratio * def[h];
      co[h] += x * m.awayGoals;
      ec[h] += x * ba[r] / ratio * att[a];
      co[a] += x * m.homeGoals;
      ec[a] += x * bh[r] * ratio * att[h];
    }
    for (let t = 0; t < T; t++) {
      att[t] = (sc[t] + kOf[t]) / (es[t] + kOf[t]);
      def[t] = (co[t] + kOf[t]) / (ec[t] + kOf[t]);
    }
    // Niveau des championnats : matchs entre championnats différents seulement.
    lsc.fill(0);
    les.fill(0);
    lco.fill(0);
    lec.fill(0);
    for (let r = 0; r < n; r++) {
      if (hl[r] === al[r]) continue;
      const h = hi[r], a = ai[r], x = w[r], m = history[r];
      const ratio = S(hl[r]) / S(al[r]);
      const eh = bh[r] * att[h] * def[a] * ratio, ea = ba[r] * att[a] * def[h] / ratio;
      if (hl[r] >= 0) {
        lsc[hl[r]] += x * m.homeGoals;
        les[hl[r]] += x * eh;
        lco[hl[r]] += x * m.awayGoals;
        lec[hl[r]] += x * ea;
      }
      if (al[r] >= 0) {
        lsc[al[r]] += x * m.awayGoals;
        les[al[r]] += x * ea;
        lco[al[r]] += x * m.homeGoals;
        lec[al[r]] += x * eh;
      }
    }
    for (let l = 0; l < L; l++) {
      const factor = Math.sqrt(((lsc[l] + leagueShrink) / (les[l] + leagueShrink)) * ((lec[l] + leagueShrink) / (lco[l] + leagueShrink)));
      lv[l] = clamp(lv[l] * factor, 0.3, 3);
    }
  }
  const attack = new Map<number, number>(), defense = new Map<number, number>(), leagueLevel = new Map<number, number>();
  for (const [id, t] of index) {
    const l = S(lidx(id));
    attack.set(id, att[t] * l);
    defense.set(id, def[t] / l);
  }
  for (const [c, l] of leagueIndex) leagueLevel.set(c, round(lv[l], 3));
  return { homeAvg, awayAvg, attack, defense, leagueLevel };
}

export function globalProbabilities(
  s: GlobalStrengths,
  competitionId: number,
  homeId: number,
  awayId: number,
  o: Model2Options = DEFAULT_OPTIONS_2,
): Record<string, number> {
  const h = s.homeAvg.get(competitionId) ?? o.priorHomeGoals;
  const a = s.awayAvg.get(competitionId) ?? o.priorAwayGoals;
  const lh = clamp(h * (s.attack.get(homeId) ?? 1) * (s.defense.get(awayId) ?? 1), 0.1, 5);
  const la = clamp(a * (s.attack.get(awayId) ?? 1) * (s.defense.get(homeId) ?? 1), 0.1, 5);
  return marketProbabilities(dixonColesMatrix(lh, la, o.rho, o.maxGoals));
}

// ---------------------------------------------------------------- recalibrage 1X2

export interface Calibration {
  t: number;
  d: number;
}

export const IDENTITY: Calibration = { t: 1, d: 0 };

export function calibrate(p: number[], c: Calibration): number[] {
  const q = p.map((x, k) => Math.max(x, EPS) ** c.t * (k === 1 ? Math.exp(c.d) : 1));
  const s = q.reduce((a, b) => a + b, 0);
  return q.map((x) => x / s);
}

/** T et d qui minimisent la perte logarithmique sur ces prédictions. */
export function fitCalibration(samples: { p: number[]; outcome: number }[], minSamples = 300): Calibration {
  if (samples.length < minSamples) return IDENTITY;
  const n = samples.length;
  const l0 = new Float64Array(n), l1 = new Float64Array(n), l2 = new Float64Array(n), lo = new Float64Array(n);
  const isDraw = new Uint8Array(n);
  samples.forEach((s, i) => {
    l0[i] = Math.log(Math.max(s.p[0], EPS));
    l1[i] = Math.log(Math.max(s.p[1], EPS));
    l2[i] = Math.log(Math.max(s.p[2], EPS));
    lo[i] = [l0[i], l1[i], l2[i]][s.outcome];
    isDraw[i] = s.outcome === 1 ? 1 : 0;
  });
  const loss = (t: number, d: number) => {
    let total = 0;
    for (let i = 0; i < n; i++) {
      const z = Math.exp(t * l0[i]) + Math.exp(t * l1[i] + d) + Math.exp(t * l2[i]);
      total -= t * lo[i] + (isDraw[i] ? d : 0) - Math.log(z);
    }
    return total;
  };
  // Descente par coordonnées, pas divisé par deux tant que rien ne s'améliore.
  let t = 1, d = 0, current = loss(t, d), step = 0.1;
  while (step >= 0.004) {
    let moved = false;
    for (const [dt, dd] of [[step, 0], [-step, 0], [0, step], [0, -step]]) {
      const nt = clamp(t + dt, 0.5, 2), nd = clamp(d + dd, -0.5, 0.5);
      const v = loss(nt, nd);
      if (v < current - 1e-9) {
        t = nt;
        d = nd;
        current = v;
        moved = true;
        break;
      }
    }
    if (!moved) step /= 2;
  }
  const best = { t: round(t, 3), d: round(d, 3) };
  return best;
}

// ---------------------------------------------------------------- mesures

class Metric {
  n = 0;
  brier = 0;
  logloss = 0;
  hits = 0;
  add(p: number[], outcome: number) {
    this.n++;
    p.forEach((x, i) => this.brier += (x - (i === outcome ? 1 : 0)) ** 2);
    this.logloss -= Math.log(Math.max(p[outcome], EPS));
    if (p.indexOf(Math.max(...p)) === outcome) this.hits++;
  }
  result() {
    const d = Math.max(this.n, 1);
    return {
      matches: this.n,
      brier: round(this.brier / d, 5),
      logloss: round(this.logloss / d, 5),
      accuracy: round(this.hits / d, 4),
    };
  }
}

class Bins {
  b = Array.from({ length: 10 }, () => [0, 0, 0]);
  add(p: number[], outcome: number) {
    p.forEach((x, k) => {
      const i = Math.min(9, Math.floor(x * 10));
      this.b[i][0]++;
      this.b[i][1] += x;
      this.b[i][2] += k === outcome ? 1 : 0;
    });
  }
  result() {
    return this.b.map(([n, sp, hits], i) => ({
      from: i / 10,
      count: n,
      predicted: n ? round(sp / n, 3) : 0,
      observed: n ? round(hits / n, 3) : 0,
    })).filter((x) => x.count > 0);
  }
}

interface Prediction {
  key: string;
  matchId: number;
  kickoffAt: string;
  homeGoals: number;
  awayGoals: number;
  base: number[];
  /** Probabilités par variante de modèle (A, B, C). */
  model: Record<string, Record<string, number>>;
  competitionId: number;
  season: number;
  homeId: number;
  awayId: number;
}

const x12 = (p: Record<string, number>) => [p["1X2.HOME"], p["1X2.DRAW"], p["1X2.AWAY"]];

/** Cotes 1X2 relevées avant le coup d'envoi → probabilités du marché, marge retirée. */
export function marketFromOdds(odds: { home: number; draw: number; away: number }): number[] | null {
  const inv = [odds.home, odds.draw, odds.away].map((o) => (o > 1 ? 1 / o : NaN));
  if (inv.some((x) => !Number.isFinite(x))) return null;
  const s = inv.reduce((a, b) => a + b, 0);
  return inv.map((x) => x / s);
}

export const blend = (model: number[], market: number[], marketWeight: number) =>
  model.map((p, k) => (1 - marketWeight) * p + marketWeight * market[k]);

export interface ExperimentOptions {
  /** Fréquence de calcul des forces reliées : chaque semaine (léger) ou chaque jour. */
  refit?: "week" | "day";
  /** Variante B (compétitions reliées sans niveau de championnat). Par défaut : oui. */
  withB?: boolean;
  /** Compétitions de type championnat : active la variante C. */
  leagues?: Set<number> | null;
}

/**
 * Expérience complète. `all` : tous les matchs terminés connus (toutes compétitions suivies),
 * pour les variantes B et C. `odds` : cotes 1X2 du dernier relevé avant le coup d'envoi.
 */
export function runExperiment(
  groups: LabGroup[],
  all: LabMatch[],
  odds: Map<number, { home: number; draw: number; away: number }> = new Map(),
  warmupMatches = 30,
  o: Model2Options = DEFAULT_OPTIONS_2,
  options: ExperimentOptions = {},
) {
  const refit = options.refit ?? "week";
  const withB = options.withB ?? true;
  const leagues = options.leagues ?? null;
  const models = ["A", ...(withB ? ["B"] : []), ...(leagues ? ["C"] : [])];
  const allSorted = [...all].sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt));

  // 1. Prédictions A (production) sur les matchs notés par l'évaluation officielle.
  const predictions: Prediction[] = [];
  for (const g of groups) {
    const sorted = [...g.matches].sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt));
    const byDay = new Map<string, ReturnType<typeof fitStrengths>>();
    const counts = [0, 0, 0];
    for (let i = 0; i < sorted.length; i++) {
      const m = sorted[i];
      let j = i;
      while (j > 0 && sorted[j - 1].kickoffAt === m.kickoffAt) j--;
      const history = sorted.slice(0, j);
      const outcome = m.homeGoals > m.awayGoals ? 0 : m.homeGoals === m.awayGoals ? 1 : 2;
      if (history.length >= warmupMatches) {
        const day = m.kickoffAt.slice(0, 10);
        let s = byDay.get(day);
        if (!s) {
          const before = [...g.prior, ...history.filter((h) => h.kickoffAt.slice(0, 10) < day)].map((h) => ({ ...h, weight: 1 }));
          s = fitStrengths(before, Date.parse(`${day}T00:00:00Z`), o);
          byDay.set(day, s);
        }
        const n = history.length;
        predictions.push({
          key: g.key,
          matchId: m.id,
          kickoffAt: m.kickoffAt,
          homeGoals: m.homeGoals,
          awayGoals: m.awayGoals,
          base: counts.map((c) => (c + 1) / (n + 3)),
          model: { A: runModel2FromStrengths(s, m.homeId, m.awayId, o).probabilities },
          competitionId: g.competitionId,
          season: g.season,
          homeId: m.homeId,
          awayId: m.awayId,
        });
      }
      counts[outcome]++;
    }
  }
  predictions.sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt));

  // 2. Variantes B et C : forces calculées au début de la semaine (ou du jour) du match, avec les
  // seuls matchs antérieurs ; une période à la fois, rien n'est gardé en mémoire ensuite.
  const periodStart = (iso: string) => {
    const t = Date.parse(`${iso.slice(0, 10)}T00:00:00Z`);
    const dow = refit === "day" ? 0 : (new Date(t).getUTCDay() + 6) % 7;
    return new Date(t - dow * DAY).toISOString();
  };
  const byPeriod = new Map<string, Prediction[]>();
  for (const p of predictions) {
    const k = `${periodStart(p.kickoffAt)}|${p.season}`;
    (byPeriod.get(k) ?? byPeriod.set(k, []).get(k)!).push(p);
  }
  let cut = 0;
  const levels: Record<string, Record<string, number>> = {};
  for (const k of [...byPeriod.keys()].sort()) {
    const [at, seasonText] = k.split("|");
    const season = Number(seasonText);
    while (cut < allSorted.length && allSorted[cut].kickoffAt < at) cut++;
    const history = allSorted.slice(0, cut);
    // Comme poisson-2.0 en production (runProductionModel, evaluate) : toutes les saisons au
    // poids 1, seule la décroissance dans le temps réduit les anciens matchs.
    const weightOf = (_m: PlayedMatch) => 1;
    void season;
    const b = withB ? fitGlobalStrengths(history, Date.parse(at), o, weightOf) : null;
    const c = leagues ? fitLeagueStrengths(history, Date.parse(at), leagues, o, weightOf) : null;
    if (c) levels[at.slice(0, 10)] = Object.fromEntries(c.leagueLevel);
    for (const p of byPeriod.get(k)!) {
      if (b) p.model.B = globalProbabilities(b, p.competitionId, p.homeId, p.awayId, o);
      if (c) p.model.C = globalProbabilities(c, p.competitionId, p.homeId, p.awayId, o);
    }
  }

  // 3. Recalibrage marche avant : réglages refaits au début de chaque mois.
  const outcomeOf = (p: Prediction) => (p.homeGoals > p.awayGoals ? 0 : p.homeGoals === p.awayGoals ? 1 : 2);
  const monthOf = (k: string) => k.slice(0, 7);
  const cal: Record<string, Map<string, Calibration>> = Object.fromEntries(models.map((v) => [v, new Map()]));
  for (const month of [...new Set(predictions.map((p) => monthOf(p.kickoffAt)))]) {
    const past = predictions.filter((p) => monthOf(p.kickoffAt) < month);
    for (const v of models) {
      cal[v].set(month, fitCalibration(past.map((p) => ({ p: x12(p.model[v]), outcome: outcomeOf(p) }))));
    }
  }

  // 4. Mesures.
  const variants = ["baseline", ...models.flatMap((v) => [v, `${v}+cal`])];
  const metrics = () => Object.fromEntries(variants.map((v) => [v, new Metric()])) as Record<string, Metric>;
  const m1x2 = metrics(), mDnb = metrics();
  const bins = Object.fromEntries(variants.map((v) => [v, new Bins()])) as Record<string, Bins>;
  const goals = Object.fromEntries(models.map((v) => [v, { ou: new Metric(), btts: new Metric() }]));
  const perComp: Record<string, Record<string, Metric>> = {};
  const marketWeights = [0, 0.3, 0.5, 0.7, 0.85, 1];
  const market: Record<string, Metric> = {};

  for (const p of predictions) {
    const outcome = outcomeOf(p);
    const month = monthOf(p.kickoffAt);
    const probs: Record<string, number[]> = { baseline: p.base };
    for (const v of models) {
      probs[v] = x12(p.model[v]);
      probs[`${v}+cal`] = calibrate(probs[v], cal[v].get(month)!);
    }
    perComp[p.key] ??= metrics();
    for (const v of variants) {
      m1x2[v].add(probs[v], outcome);
      bins[v].add(probs[v], outcome);
      perComp[p.key][v].add(probs[v], outcome);
      if (outcome !== 1) {
        const q = probs[v];
        mDnb[v].add([q[0] / (q[0] + q[2]), q[2] / (q[0] + q[2])], outcome === 0 ? 0 : 1);
      }
    }
    const over = p.homeGoals + p.awayGoals > 2.5 ? 0 : 1;
    const btts = p.homeGoals > 0 && p.awayGoals > 0 ? 0 : 1;
    for (const v of models) {
      const q = p.model[v];
      goals[v].ou.add([q["OU.OVER.2.5"], 1 - q["OU.OVER.2.5"]], over);
      goals[v].btts.add([q["BTTS.YES"], 1 - q["BTTS.YES"]], btts);
    }
    const o1x2 = odds.get(p.matchId);
    const mkt = o1x2 ? marketFromOdds(o1x2) : null;
    if (mkt) {
      for (const v of models) {
        for (const w of marketWeights) (market[`${v}+cal / marché ${w}`] ??= new Metric()).add(blend(probs[`${v}+cal`], mkt, w), outcome);
      }
    }
  }

  const res = (r: Record<string, Metric>) => Object.fromEntries(variants.map((v) => [v, r[v].result()]));
  const lastMonth = monthOf(predictions.at(-1)?.kickoffAt ?? "");
  const lastLevels = Object.keys(levels).sort().at(-1);
  return {
    matches: predictions.length,
    oneXTwo: res(m1x2),
    dnb: res(mDnb),
    goals: {
      over_2_5: Object.fromEntries(models.map((v) => [v, goals[v].ou.result()])),
      btts: Object.fromEntries(models.map((v) => [v, goals[v].btts.result()])),
    },
    calibration: Object.fromEntries(variants.filter((v) => v !== "baseline").map((v) => [v, bins[v].result()])),
    calibration_settings_latest: Object.fromEntries(models.map((v) => [v, cal[v].get(lastMonth)])),
    league_levels_latest: lastLevels ? levels[lastLevels] : null,
    per_competition_logloss: Object.fromEntries(
      Object.entries(perComp).map(([k, r]) => [k, {
        matches: r.A.n,
        ...Object.fromEntries(variants.map((v) => [v, r[v].result().logloss])),
      }]),
    ) as Record<string, { matches: number } & Record<string, number>>,
    market: Object.fromEntries(Object.entries(market).map(([k, v]) => [k, v.result()])),
  };
}
