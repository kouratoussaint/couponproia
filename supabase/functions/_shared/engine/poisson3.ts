// Moteur statistique « poisson-3.0 » (LOT 28, issu de l'expérience « Moteur 3.0 » du 08/11/2026).
//
// Différences avec poisson-2.0 :
//  1. Compétitions reliées : les forces d'une équipe viennent de TOUS ses matchs connus
//     (championnat, coupes d'Europe et d'Afrique…), avec la moyenne de buts et l'avantage du
//     terrain propres à la compétition de chaque match.
//  2. Niveau des championnats : chaque équipe est rattachée au championnat (type « league ») où
//     elle a le plus joué ; ses forces sont relatives à ce championnat, et le niveau S du
//     championnat multiplie l'attaque et divise la défense. S s'annule dans un match de
//     championnat ; il n'est estimé que sur les matchs entre équipes de championnats différents
//     (coupes continentales), rétréci vers 1. Sans championnat suivi : S = 1.
//  3. Prudence (matchs fictifs) propre à chaque équipe, selon le niveau de buts de ses matchs :
//     une équipe qui ne joue qu'une compétition retrouve exactement poisson-2.0.
//  Inchangé : décroissance dans le temps (demi-vie 730 jours, toutes saisons au poids 1),
//  rétrécissement k = 5, a priori de 20 matchs par compétition, loi de Poisson.
// Les forces sont calculées jusqu'à leur point fixe (et non un nombre fixe d'itérations), ce qui
// permet de reprendre le calcul de la veille (évaluation jour par jour). Fonctions pures.
import { marketProbabilities, type ModelResult, type PlayedMatch, reliabilityFor, round, topScores } from "./poisson.ts";
import { DEFAULT_OPTIONS_2, dixonColesMatrix, type Model2Options } from "./poisson2.ts";

export const ENGINE_VERSION_3 = "poisson-3.0";

export interface Model3Options extends Model2Options {
  /** Buts fictifs qui rapprochent le niveau d'un championnat de 1. */
  leagueShrink: number;
  /** Écart relatif maximal entre deux itérations pour considérer le calcul terminé. */
  tolerance: number;
  maxIterations: number;
}

export const DEFAULT_OPTIONS_3: Model3Options = {
  ...DEFAULT_OPTIONS_2,
  leagueShrink: 10,
  // 0,01 % d'écart entre deux itérations : effet sur les probabilités bien inférieur au millième.
  tolerance: 1e-4,
  maxIterations: 400,
};

export interface Match3 extends PlayedMatch {
  competitionId: number;
}

/** Forces à une date : tout ce qu'il faut pour prédire un match (et l'expliquer). */
export interface Strengths3 {
  at: string;
  /** Moyennes de buts domicile / extérieur par compétition. */
  homeAvg: Map<number, number>;
  awayAvg: Map<number, number>;
  /** Attaque et défense effectives (niveau du championnat inclus). */
  attack: Map<number, number>;
  defense: Map<number, number>;
  /** Niveau de chaque championnat national (1 = équipes sans championnat suivi). */
  leagueLevel: Map<number, number>;
  /** Matchs joués sur les 365 derniers jours, par équipe et par compétition. */
  played: Map<number, number>;
  competitionMatches: Map<number, number>;
}

const DAY = 86400_000;
/** Référence fixe des poids (les poids relatifs ne dépendent pas de la date du calcul). */
const T0 = Date.UTC(2020, 0, 1);
const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x));

/**
 * Modèle incrémental : on ajoute les matchs dans l'ordre chronologique, puis on calcule les
 * forces à une date (avec les seuls matchs déjà ajoutés). Le calcul repart du résultat
 * précédent : à quelques matchs près, il converge en quelques itérations.
 */
export class LeagueModel {
  readonly o: Model3Options;
  private readonly leagues: Set<number>;
  // Matchs (tableaux parallèles).
  private ci: number[] = [];
  private hi: number[] = [];
  private ai: number[] = [];
  private hg: number[] = [];
  private ag: number[] = [];
  private w: number[] = [];
  private t: number[] = [];
  private lastAt = -Infinity;
  // Index.
  private teamIndex = new Map<number, number>();
  private teamIds: number[] = [];
  private compIndex = new Map<number, number>();
  private compIds: number[] = [];
  // Sommes par compétition (poids bruts).
  private cw: number[] = [];
  private ch: number[] = [];
  private ca: number[] = [];
  // Championnat de rattachement : nombre de matchs de championnat par équipe, dans l'ordre.
  private leagueCounts: Map<number, number>[] = [];
  /** Poids bruts de chaque équipe par compétition (pour sa prudence). */
  private teamCompWeight: Map<number, number>[] = [];
  // Solution courante (reprise d'un calcul à l'autre).
  private att: number[] = [];
  private def: number[] = [];
  private level = new Map<number, number>();
  /** Itérations du dernier calcul (suivi des performances). */
  lastIterations = 0;

  constructor(leagues: Set<number>, o: Model3Options = DEFAULT_OPTIONS_3) {
    this.leagues = leagues;
    this.o = o;
  }

  get size() {
    return this.ci.length;
  }

  private team(id: number) {
    let i = this.teamIndex.get(id);
    if (i === undefined) {
      i = this.teamIds.length;
      this.teamIndex.set(id, i);
      this.teamIds.push(id);
      this.leagueCounts.push(new Map());
      this.teamCompWeight.push(new Map());
      this.att.push(1);
      this.def.push(1);
    }
    return i;
  }

  private comp(id: number) {
    let i = this.compIndex.get(id);
    if (i === undefined) {
      i = this.compIds.length;
      this.compIndex.set(id, i);
      this.compIds.push(id);
      this.cw.push(0);
      this.ch.push(0);
      this.ca.push(0);
    }
    return i;
  }

  /** Ajoute un match terminé ; les matchs doivent arriver par date croissante. */
  add(m: Match3) {
    const time = Date.parse(m.kickoffAt);
    if (time < this.lastAt) throw new Error("LeagueModel.add : matchs hors de l'ordre chronologique");
    this.lastAt = time;
    const c = this.comp(m.competitionId), h = this.team(m.homeId), a = this.team(m.awayId);
    const w = (m.weight ?? 1) * 2 ** ((time - T0) / DAY / this.o.halfLifeDays);
    this.ci.push(c);
    this.hi.push(h);
    this.ai.push(a);
    this.hg.push(m.homeGoals);
    this.ag.push(m.awayGoals);
    this.w.push(w);
    this.t.push(time);
    this.cw[c] += w;
    this.ch[c] += w * m.homeGoals;
    this.ca[c] += w * m.awayGoals;
    for (const x of [h, a]) {
      this.teamCompWeight[x].set(c, (this.teamCompWeight[x].get(c) ?? 0) + w);
      if (this.leagues.has(m.competitionId)) {
        this.leagueCounts[x].set(m.competitionId, (this.leagueCounts[x].get(m.competitionId) ?? 0) + 1);
      }
    }
  }

  /** Forces à la date `at` (ms), avec tous les matchs ajoutés jusqu'ici. */
  solve(at: number): Strengths3 {
    const o = this.o;
    const n = this.ci.length, T = this.teamIds.length, C = this.compIds.length;
    // Facteur d'échelle : poids réel = poids brut / scale.
    const scale = 2 ** ((at - T0) / DAY / o.halfLifeDays);
    const p = o.leaguePriorMatches * scale;
    const avgH: number[] = [], avgA: number[] = [];
    for (let c = 0; c < C; c++) {
      avgH.push((this.ch[c] + p * o.priorHomeGoals) / (this.cw[c] + p));
      avgA.push((this.ca[c] + p * o.priorAwayGoals) / (this.cw[c] + p));
    }
    // Championnat de rattachement (le premier atteint à égalité) et prudence de chaque équipe.
    const leagueOfTeam: number[] = new Array(T);
    const levelIndex = new Map<number, number>();
    const levelIds: number[] = [];
    let totalW = 0, totalG = 0;
    for (let c = 0; c < C; c++) {
      totalW += this.cw[c];
      totalG += this.cw[c] * (avgH[c] + avgA[c]);
    }
    const fallback = totalW > 0 ? totalG / totalW / 2 : (o.priorHomeGoals + o.priorAwayGoals) / 2;
    const kOf: number[] = new Array(T);
    for (let x = 0; x < T; x++) {
      let best = -1, most = 0;
      for (const [c, k] of this.leagueCounts[x]) if (k > most) [best, most] = [c, k];
      if (best >= 0 && !levelIndex.has(best)) {
        levelIndex.set(best, levelIds.length);
        levelIds.push(best);
      }
      leagueOfTeam[x] = best < 0 ? -1 : levelIndex.get(best)!;
      let kw = 0, kg = 0;
      for (const [c, w] of this.teamCompWeight[x]) {
        kw += w;
        kg += w * (avgH[c] + avgA[c]) / 2;
      }
      kOf[x] = o.shrinkK * (kw > 0 ? kg / kw : fallback) * scale;
    }
    const L = levelIds.length;
    const lv: number[] = levelIds.map((id) => this.level.get(id) ?? 1);
    const S = (l: number) => (l < 0 ? 1 : lv[l]);
    const ls = o.leagueShrink * scale;

    const att = this.att, def = this.def;
    const sc = new Float64Array(T), es = new Float64Array(T), co = new Float64Array(T), ec = new Float64Array(T);
    const lsc = new Float64Array(L), les = new Float64Array(L), lco = new Float64Array(L), lec = new Float64Array(L);
    const ci = this.ci, hi = this.hi, ai = this.ai, hg = this.hg, ag = this.ag, w = this.w;
    for (let it = 0; it < o.maxIterations; it++) {
      // Attaque puis défense, chacune avec la dernière valeur de l'autre (converge plus vite
      // qu'une mise à jour simultanée, même point fixe).
      sc.fill(0);
      es.fill(0);
      for (let r = 0; r < n; r++) {
        const h = hi[r], a = ai[r], x = w[r], c = ci[r];
        const ratio = S(leagueOfTeam[h]) / S(leagueOfTeam[a]);
        sc[h] += x * hg[r];
        es[h] += x * avgH[c] * ratio * def[a];
        sc[a] += x * ag[r];
        es[a] += x * avgA[c] / ratio * def[h];
      }
      let change = 0;
      for (let x = 0; x < T; x++) {
        const na = (sc[x] + kOf[x]) / (es[x] + kOf[x]);
        change = Math.max(change, Math.abs(na / att[x] - 1));
        att[x] = na;
      }
      co.fill(0);
      ec.fill(0);
      for (let r = 0; r < n; r++) {
        const h = hi[r], a = ai[r], x = w[r], c = ci[r];
        const ratio = S(leagueOfTeam[h]) / S(leagueOfTeam[a]);
        co[h] += x * ag[r];
        ec[h] += x * avgA[c] / ratio * att[a];
        co[a] += x * hg[r];
        ec[a] += x * avgH[c] * ratio * att[h];
      }
      for (let x = 0; x < T; x++) {
        const nd = (co[x] + kOf[x]) / (ec[x] + kOf[x]);
        change = Math.max(change, Math.abs(nd / def[x] - 1));
        def[x] = nd;
      }
      if (L > 0) {
        lsc.fill(0);
        les.fill(0);
        lco.fill(0);
        lec.fill(0);
        for (let r = 0; r < n; r++) {
          const lh = leagueOfTeam[hi[r]], la = leagueOfTeam[ai[r]];
          if (lh === la) continue;
          const h = hi[r], a = ai[r], x = w[r], c = ci[r];
          const ratio = S(lh) / S(la);
          const eh = avgH[c] * att[h] * def[a] * ratio, ea = avgA[c] * att[a] * def[h] / ratio;
          if (lh >= 0) {
            lsc[lh] += x * hg[r];
            les[lh] += x * eh;
            lco[lh] += x * ag[r];
            lec[lh] += x * ea;
          }
          if (la >= 0) {
            lsc[la] += x * ag[r];
            les[la] += x * ea;
            lco[la] += x * hg[r];
            lec[la] += x * eh;
          }
        }
        for (let l = 0; l < L; l++) {
          const f = Math.sqrt(((lsc[l] + ls) / (les[l] + ls)) * ((lec[l] + ls) / (lco[l] + ls)));
          const next = clamp(lv[l] * f, 0.3, 3);
          change = Math.max(change, Math.abs(next / lv[l] - 1));
          lv[l] = next;
        }
      }
      this.lastIterations = it + 1;
      if (change < o.tolerance) break;
    }
    levelIds.forEach((id, l) => this.level.set(id, lv[l]));

    // Résultat, avec le volume de matchs des 365 derniers jours (fiabilité affichée).
    const since = at - 365 * DAY;
    const playedRaw = new Float64Array(T), compRaw = new Float64Array(C);
    for (let r = n - 1; r >= 0 && this.t[r] >= since; r--) {
      if (this.t[r] >= at) continue;
      playedRaw[hi[r]]++;
      playedRaw[ai[r]]++;
      compRaw[ci[r]]++;
    }
    const s: Strengths3 = {
      at: new Date(at).toISOString(),
      homeAvg: new Map(),
      awayAvg: new Map(),
      attack: new Map(),
      defense: new Map(),
      leagueLevel: new Map(levelIds.map((id, l) => [id, lv[l]])),
      played: new Map(),
      competitionMatches: new Map(),
    };
    this.compIds.forEach((id, c) => {
      s.homeAvg.set(id, avgH[c]);
      s.awayAvg.set(id, avgA[c]);
      s.competitionMatches.set(id, compRaw[c]);
    });
    this.teamIds.forEach((id, x) => {
      const l = S(leagueOfTeam[x]);
      s.attack.set(id, att[x] * l);
      s.defense.set(id, def[x] / l);
      s.played.set(id, playedRaw[x]);
    });
    return s;
  }
}

/** Forces à une date à partir d'une liste de matchs (ceux d'avant la date sont retenus). */
export function strengthsAt(matches: Match3[], at: number, leagues: Set<number>, o: Model3Options = DEFAULT_OPTIONS_3) {
  const model = new LeagueModel(leagues, o);
  for (const m of [...matches].sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt))) {
    if (Date.parse(m.kickoffAt) < at) model.add({ ...m, weight: 1 });
  }
  return model.solve(at);
}

/** Probabilités et détails d'un match avec poisson-3.0. */
export function runModel3(
  s: Strengths3,
  competitionId: number,
  homeId: number,
  awayId: number,
  o: Model3Options = DEFAULT_OPTIONS_3,
): ModelResult {
  const h = s.homeAvg.get(competitionId) ?? o.priorHomeGoals;
  const a = s.awayAvg.get(competitionId) ?? o.priorAwayGoals;
  const lambdaHome = clamp(h * (s.attack.get(homeId) ?? 1) * (s.defense.get(awayId) ?? 1), 0.1, 5);
  const lambdaAway = clamp(a * (s.attack.get(awayId) ?? 1) * (s.defense.get(homeId) ?? 1), 0.1, 5);
  const matrix = dixonColesMatrix(lambdaHome, lambdaAway, o.rho, o.maxGoals);
  const homePlayed = s.played.get(homeId) ?? 0;
  const awayPlayed = s.played.get(awayId) ?? 0;
  return {
    lambdaHome: round(lambdaHome, 2),
    lambdaAway: round(lambdaAway, 2),
    leagueHomeAvg: round(h, 2),
    leagueAwayAvg: round(a, 2),
    sample: {
      leagueMatches: s.competitionMatches.get(competitionId) ?? 0,
      homeTeamHomeMatches: round(homePlayed / 2, 1),
      awayTeamAwayMatches: round(awayPlayed / 2, 1),
    },
    // Même échelle que poisson-2.0 : la moitié des matchs d'une équipe se jouent à domicile.
    reliability: reliabilityFor(homePlayed / 2, awayPlayed / 2),
    probabilities: marketProbabilities(matrix),
    topScores: topScores(matrix),
  };
}

// ---------------------------------------------------------------- photo enregistrée (engine_strengths)

export interface StrengthsSnapshot {
  engine_version: string;
  at: string;
  competitions: Record<string, [number, number, number]>;
  teams: Record<string, [number, number, number]>;
  leagues: Record<string, number>;
}

export function toSnapshot(s: Strengths3): StrengthsSnapshot {
  const r = (x: number) => Math.round(x * 1e6) / 1e6;
  return {
    engine_version: ENGINE_VERSION_3,
    at: s.at,
    competitions: Object.fromEntries(
      [...s.homeAvg.keys()].map((id) => [String(id), [r(s.homeAvg.get(id)!), r(s.awayAvg.get(id)!), s.competitionMatches.get(id) ?? 0]]),
    ),
    teams: Object.fromEntries(
      [...s.attack.keys()].map((id) => [String(id), [r(s.attack.get(id)!), r(s.defense.get(id)!), s.played.get(id) ?? 0]]),
    ),
    leagues: Object.fromEntries([...s.leagueLevel].map(([id, v]) => [String(id), r(v)])),
  };
}

export function fromSnapshot(x: StrengthsSnapshot): Strengths3 {
  const s: Strengths3 = {
    at: x.at,
    homeAvg: new Map(),
    awayAvg: new Map(),
    attack: new Map(),
    defense: new Map(),
    leagueLevel: new Map(Object.entries(x.leagues).map(([k, v]) => [Number(k), v])),
    played: new Map(),
    competitionMatches: new Map(),
  };
  for (const [k, [h, a, n]] of Object.entries(x.competitions)) {
    s.homeAvg.set(Number(k), h);
    s.awayAvg.set(Number(k), a);
    s.competitionMatches.set(Number(k), n);
  }
  for (const [k, [att, def, played]] of Object.entries(x.teams)) {
    s.attack.set(Number(k), att);
    s.defense.set(Number(k), def);
    s.played.set(Number(k), played);
  }
  return s;
}
