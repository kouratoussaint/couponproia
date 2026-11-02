// Générateur de coupons de la plateforme (fonctions pures, testables).
//
// 1. Candidats : chaque issue cotée d'un match à venir, avec la probabilité du modèle,
//    la probabilité implicite du marché (marge retirée), l'écart et la fiabilité.
// 2. Filtres du profil : marchés autorisés et validés par l'évaluation, cotes, seuils.
// 3. Combinaison : au plus une sélection par match ; parmi les combinaisons dont la cote
//    totale est dans la fourchette, on retient celle que le modèle juge la plus probable.
// 4. Contrôle qualité : tout est revérifié juste avant l'enregistrement et la publication.
// Les cotes totales et probabilités sont calculées ici (jamais par l'IA).
import { round } from "../engine/poisson.ts";

export type Reliability = "faible" | "moyenne" | "bonne";
const RELIABILITY_RANK: Record<Reliability, number> = { faible: 0, moyenne: 1, bonne: 2 };

export interface Criteria {
  min_selections: number;
  max_selections: number;
  min_total_odd: number;
  max_total_odd: number;
  min_selection_odd: number;
  max_selection_odd: number;
  coupons_per_run: number;
  /** Identifiants de compétitions autorisées ; vide = toutes les compétitions suivies. */
  competitions: number[];
  /** Familles de marchés : 1X2, DC, OU, BTTS. */
  markets: string[];
  /** Issues précises autorisées (« OU.OVER.1.5 »…) ; vide = toutes celles des marchés retenus. */
  allowed_keys: string[];
  min_model_probability: number;
  min_edge: number;
  /** Écart maximal avec le marché : au-delà, le désaccord trahit plus souvent une lacune du modèle. */
  max_edge: number;
  min_reliability: Reliability;
  window_hours: number;
  min_minutes_before_kickoff: number;
  max_odds_age_hours: number;
  /** N'utiliser que les familles où le moteur bat la référence sur l'historique. */
  require_validated_markets: boolean;
  /** Plafond de sélections d'une même compétition dans un coupon (0 = pas de plafond). */
  max_per_competition: number;
  /** Coupons de la même catégorie par jour de match (heure locale) ; null = règle de la catégorie. */
  max_per_day: number | null;
}

export const DEFAULT_CRITERIA: Criteria = {
  min_selections: 2,
  max_selections: 4,
  min_total_odd: 2.5,
  max_total_odd: 5,
  min_selection_odd: 1.25,
  max_selection_odd: 3,
  coupons_per_run: 1,
  competitions: [],
  markets: ["1X2", "DC"],
  allowed_keys: [],
  min_model_probability: 0.5,
  min_edge: -0.02,
  max_edge: 0.06,
  min_reliability: "moyenne",
  window_hours: 24,
  min_minutes_before_kickoff: 30,
  max_odds_age_hours: 12,
  require_validated_markets: true,
  max_per_competition: 0,
  max_per_day: null,
};

/** Critères d'un profil (JSON libre) complétés par les valeurs par défaut et bornés. */
export function parseCriteria(raw: unknown): Criteria {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const num = (k: keyof Criteria, lo: number, hi: number) => {
    const v = Number(r[k]);
    return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : DEFAULT_CRITERIA[k] as number;
  };
  const c: Criteria = {
    min_selections: Math.round(num("min_selections", 1, 12)),
    max_selections: Math.round(num("max_selections", 1, 12)),
    min_total_odd: num("min_total_odd", 1.01, 10000),
    max_total_odd: num("max_total_odd", 1.01, 10000),
    min_selection_odd: num("min_selection_odd", 1.01, 100),
    max_selection_odd: num("max_selection_odd", 1.01, 100),
    coupons_per_run: Math.round(num("coupons_per_run", 1, 10)),
    competitions: Array.isArray(r.competitions) ? r.competitions.map(Number).filter(Number.isInteger) : [],
    markets: Array.isArray(r.markets) && r.markets.length ? r.markets.map(String) : DEFAULT_CRITERIA.markets,
    allowed_keys: Array.isArray(r.allowed_keys) ? r.allowed_keys.map(String) : [],
    min_model_probability: num("min_model_probability", 0, 1),
    min_edge: num("min_edge", -1, 1),
    max_edge: num("max_edge", 0, 1),
    min_reliability: (["faible", "moyenne", "bonne"].includes(String(r.min_reliability))
      ? r.min_reliability
      : DEFAULT_CRITERIA.min_reliability) as Reliability,
    window_hours: num("window_hours", 1, 168),
    min_minutes_before_kickoff: num("min_minutes_before_kickoff", 0, 720),
    max_odds_age_hours: num("max_odds_age_hours", 1, 72),
    require_validated_markets: r.require_validated_markets === undefined
      ? DEFAULT_CRITERIA.require_validated_markets
      : r.require_validated_markets === true,
    max_per_competition: Math.round(num("max_per_competition", 0, 12)),
    max_per_day: r.max_per_day === undefined || r.max_per_day === null || !Number.isFinite(Number(r.max_per_day))
      ? null
      : Math.round(Math.min(20, Math.max(0, Number(r.max_per_day)))),
  };
  if (c.max_selections < c.min_selections) c.max_selections = c.min_selections;
  if (c.max_total_odd < c.min_total_odd) c.max_total_odd = c.min_total_odd;
  if (c.max_selection_odd < c.min_selection_odd) c.max_selection_odd = c.min_selection_odd;
  if (c.max_edge < c.min_edge) c.max_edge = c.min_edge;
  return c;
}

export interface Candidate {
  matchId: number;
  competitionId: number;
  competitionName: string;
  kickoffAt: string;
  home: string;
  away: string;
  /** Clé normalisée de l'issue : « 1X2.HOME », « DC.1X », « OU.OVER.2.5 »… */
  key: string;
  marketCode: string;
  outcomeCode: string;
  line: number | null;
  odd: number;
  oddBest: number;
  bookmakers: number;
  oddsCapturedAt: string;
  modelProbability: number;
  impliedProbability: number | null;
  edge: number | null;
  /** Probabilité du modèle seul, avant le mélange avec le marché (absente si pas de mélange). */
  rawModelProbability?: number;
  /** Écart du modèle seul avec le marché : c'est lui que filtrent min_edge et max_edge. */
  rawEdge?: number | null;
  reliability: Reliability;
  justification: string;
}

/**
 * Mélange modèle / marché (proposition validée le 31/10) : la probabilité retenue est
 * (1 − w) × modèle + w × marché. Le marché intègre des informations que le modèle ignore
 * (absents, compositions) ; le mélange tempère les désaccords. Sans cote, rien ne change.
 */
export function blendWithMarket(candidates: Candidate[], marketWeight: number): Candidate[] {
  const w = Math.min(1, Math.max(0, marketWeight));
  if (w === 0) return candidates;
  return candidates.map((c) => {
    if (c.impliedProbability === null) return c;
    const p = round((1 - w) * c.modelProbability + w * c.impliedProbability, 4);
    const edge = round(p - c.impliedProbability, 4);
    const raw = c.modelProbability;
    const rest = c.justification.includes(" ; ") ? c.justification.slice(c.justification.indexOf(" ; ")) : ".";
    return {
      ...c,
      rawModelProbability: raw,
      rawEdge: c.edge,
      modelProbability: p,
      edge,
      justification: `Estimation retenue : ${pct(p)} (modèle ${pct(raw)}, marché ${pct(c.impliedProbability)})${rest}`,
    };
  });
}

/** Utilisation d'un match dans les coupons en circulation. */
export interface MatchUsage {
  count: number;
  categories: Set<string>;
}

/** Catégories qui ne partagent aucun match (le Coupon du jour et le Coupon prudent). */
export const EXCLUSIVE_CATEGORIES: Record<string, string[]> = {
  du_jour: ["prudent"],
  prudent: ["du_jour"],
};

/**
 * Diversification (proposition validée le 31/10) : un match figure dans `maxUses` coupons
 * en circulation au plus, et jamais à la fois dans deux catégories exclusives. Un seul
 * pronostic raté ne fait plus tomber tous les coupons de la journée.
 */
export function diversify(
  candidates: Candidate[],
  usage: Map<number, MatchUsage>,
  category: string,
  maxUses: number,
): { kept: Candidate[]; excluded: Record<string, number> } {
  const excluded: Record<string, number> = {};
  const exclusive = EXCLUSIVE_CATEGORIES[category] ?? [];
  const kept = candidates.filter((c) => {
    const u = usage.get(c.matchId);
    if (!u) return true;
    let reason: string | null = null;
    if (u.categories.has(category)) reason = "match déjà dans un coupon de la même catégorie";
    else if (exclusive.some((x) => u.categories.has(x))) reason = "match déjà dans le coupon jumelé (du jour / prudent)";
    else if (maxUses > 0 && u.count >= maxUses) reason = `match déjà dans ${u.count} coupons en circulation`;
    if (!reason) return true;
    excluded[reason] = (excluded[reason] ?? 0) + 1;
    return false;
  });
  return { kept, excluded };
}

/** Ajoute les matchs d'un coupon créé à l'utilisation en cours. */
export function recordUsage(usage: Map<number, MatchUsage>, selections: Pick<Candidate, "matchId">[], category: string) {
  for (const s of selections) {
    const u = usage.get(s.matchId) ?? { count: 0, categories: new Set<string>() };
    u.count++;
    u.categories.add(category);
    usage.set(s.matchId, u);
  }
}

/** Famille d'un marché pour les critères (1X2, DC, OU, BTTS, DNB, TTH, TTA). */
export const familyOf = (key: string) => key.split(".")[0];
/** Famille d'évaluation : la double chance dépend du 1X2 ; buts par équipe → TT. */
export const qualityFamilyOf = (key: string) => {
  const f = familyOf(key);
  if (f === "DC") return "1X2";
  if (f === "TTH" || f === "TTA") return "TT";
  return f;
};

const HOUR = 3600_000;

/** Applique les critères du profil ; compte les candidats écartés par motif. */
export function filterCandidates(
  candidates: Candidate[],
  criteria: Criteria,
  now: Date,
  beatsBaseline: Record<string, boolean> | null,
  competitionQuality: Record<string, boolean> = {},
): { kept: Candidate[]; excluded: Record<string, number> } {
  const excluded: Record<string, number> = {};
  const out = (reason: string) => {
    excluded[reason] = (excluded[reason] ?? 0) + 1;
    return false;
  };
  const t = now.getTime();
  const kept = candidates.filter((c) => {
    const kickoff = Date.parse(c.kickoffAt);
    if (kickoff - t < criteria.min_minutes_before_kickoff * 60_000) return out("coup d'envoi trop proche");
    if (kickoff - t > criteria.window_hours * HOUR) return out("hors fenêtre de matchs");
    if (criteria.competitions.length && !criteria.competitions.includes(c.competitionId)) {
      return out("compétition non retenue");
    }
    if (!criteria.markets.includes(familyOf(c.key))) return out("marché non retenu");
    if (criteria.allowed_keys.length && !criteria.allowed_keys.includes(c.key)) return out("issue non demandée");
    if (criteria.require_validated_markets && beatsBaseline?.[qualityFamilyOf(c.key)] !== true) {
      return out("marché non validé par l'évaluation du moteur");
    }
    if (criteria.require_validated_markets && competitionQuality[c.competitionName] === false) {
      return out("compétition où le moteur ne bat pas la référence");
    }
    if (t - Date.parse(c.oddsCapturedAt) > criteria.max_odds_age_hours * HOUR) return out("cote trop ancienne");
    if (c.odd < criteria.min_selection_odd || c.odd > criteria.max_selection_odd) return out("cote hors fourchette");
    if (c.modelProbability < criteria.min_model_probability) return out("probabilité du modèle trop faible");
    const edge = c.rawEdge !== undefined ? c.rawEdge : c.edge;
    if (edge === null || edge < criteria.min_edge) return out("écart avec le marché insuffisant");
    if (edge > criteria.max_edge) return out("désaccord trop fort avec le marché");
    if (RELIABILITY_RANK[c.reliability] < RELIABILITY_RANK[criteria.min_reliability]) return out("fiabilité insuffisante");
    return true;
  });
  return { kept, excluded };
}

export interface ProposedCoupon {
  selections: Candidate[];
  totalOdd: number;
  combinedProbability: number;
  impliedProbability: number | null;
  fingerprint: string;
}

export function fingerprintOf(selections: Pick<Candidate, "matchId" | "key">[]): string {
  return selections.map((s) => `${s.matchId}:${s.key}`).sort().join("|");
}

export function totalOddOf(selections: Pick<Candidate, "odd">[]): number {
  return round(selections.reduce((p, s) => p * s.odd, 1), 2);
}

export function propose(selections: Candidate[]): ProposedCoupon {
  const sorted = [...selections].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt) || a.matchId - b.matchId);
  const implied = sorted.every((s) => s.impliedProbability !== null)
    ? round(sorted.reduce((p, s) => p * (s.impliedProbability as number), 1), 4)
    : null;
  return {
    selections: sorted,
    totalOdd: totalOddOf(sorted),
    combinedProbability: round(sorted.reduce((p, s) => p * s.modelProbability, 1), 4),
    impliedProbability: implied,
    fingerprint: fingerprintOf(sorted),
  };
}

/**
 * Cherche jusqu'à `coupons_per_run` coupons : pour chacun, la combinaison la plus probable
 * (selon le modèle, matchs supposés indépendants) dont la cote totale est dans la fourchette.
 * Les coupons d'une même génération diffèrent d'au moins la moitié de leurs sélections ;
 * les empreintes déjà en circulation sont exclues.
 */
export function buildCoupons(
  candidates: Candidate[],
  criteria: Criteria,
  takenFingerprints: Set<string> = new Set(),
  maxNodes = 200_000,
  /** Sélections imposées (équipes demandées, sélections conservées lors d'une modification). */
  fixed: Candidate[] = [],
): ProposedCoupon[] {
  const fixedMatches = new Set(fixed.map((f) => f.matchId));
  const pool = searchPool(candidates.filter((c) => !fixedMatches.has(c.matchId)), criteria, fixed);
  const results: ProposedCoupon[] = [];
  const taken = new Set(takenFingerprints);
  const minLog = Math.log(criteria.min_total_odd);
  const maxLog = Math.log(criteria.max_total_odd) + 1e-9;

  for (let k = 0; k < criteria.coupons_per_run; k++) {
    const state: { best: Candidate[] | null; bestLogP: number } = { best: null, bestLogP: -Infinity };
    let nodes = 0;
    const chosen: Candidate[] = [...fixed];
    const matches = new Set<number>(fixedMatches);
    const perCompetition = new Map<number, number>();
    for (const f of fixed) perCompetition.set(f.competitionId, (perCompetition.get(f.competitionId) ?? 0) + 1);
    const fixedLogOdd = fixed.reduce((s, f) => s + Math.log(f.odd), 0);
    const fixedLogP = fixed.reduce((s, f) => s + Math.log(f.modelProbability), 0);

    const overlapsTooMuch = (sel: Candidate[]) =>
      results.some((r) => {
        if (fixed.length) return fingerprintOf(sel) === r.fingerprint;
        const keys = new Set(r.selections.map((s) => `${s.matchId}:${s.key}`));
        const common = sel.filter((s) => keys.has(`${s.matchId}:${s.key}`)).length;
        return common > Math.floor(Math.min(sel.length, r.selections.length) / 2);
      });

    const dfs = (start: number, logOdd: number, logP: number) => {
      if (++nodes > maxNodes) return;
      if (logP <= state.bestLogP) return; // ajouter une sélection ne peut que baisser la probabilité
      if (chosen.length >= criteria.min_selections && logOdd >= minLog - 1e-9 && logOdd <= maxLog) {
        const fp = fingerprintOf(chosen);
        if (!taken.has(fp) && !overlapsTooMuch(chosen)) {
          state.best = [...chosen];
          state.bestLogP = logP;
        }
      }
      if (chosen.length >= criteria.max_selections) return;
      for (let i = start; i < pool.length; i++) {
        const c = pool[i];
        if (matches.has(c.matchId)) continue;
        const nextLogOdd = logOdd + Math.log(c.odd);
        if (nextLogOdd > maxLog) continue;
        const count = perCompetition.get(c.competitionId) ?? 0;
        if (criteria.max_per_competition > 0 && count >= criteria.max_per_competition) continue;
        chosen.push(c);
        matches.add(c.matchId);
        perCompetition.set(c.competitionId, count + 1);
        dfs(i + 1, nextLogOdd, logP + Math.log(c.modelProbability));
        chosen.pop();
        matches.delete(c.matchId);
        perCompetition.set(c.competitionId, count);
      }
    };
    if (fixedLogOdd <= maxLog) dfs(0, fixedLogOdd, fixedLogP);
    if (!state.best) break;
    const proposal = propose(state.best);
    results.push(proposal);
    taken.add(proposal.fingerprint);
  }
  return results;
}

/**
 * Candidats retenus pour la recherche. Les 40 plus probables ne suffisent pas : ce sont surtout
 * des cotes basses (doubles chances à 1,20) qui n'atteignent jamais une cote totale de 4 en
 * 3 sélections. On ajoute donc les plus proches de la cote « idéale » par sélection.
 */
export function searchPool(candidates: Candidate[], criteria: Criteria, fixed: Candidate[] = []): Candidate[] {
  const byProbability = (a: Candidate, b: Candidate) =>
    b.modelProbability - a.modelProbability || (b.edge ?? 0) - (a.edge ?? 0);
  const free = Math.max(1, (criteria.min_selections + criteria.max_selections) / 2 - fixed.length);
  const fixedLog = fixed.reduce((s, f) => s + Math.log(f.odd), 0);
  const targetLog = (Math.log(Math.sqrt(criteria.min_total_odd * criteria.max_total_odd)) - fixedLog) / free;
  const closeness = (c: Candidate) => Math.abs(Math.log(c.odd) - targetLog);
  const chosen = new Map<Candidate, true>();
  [...candidates].sort(byProbability).slice(0, 40).forEach((c) => chosen.set(c, true));
  [...candidates]
    .filter((c) => Math.abs(Math.log(c.odd) - targetLog) < 0.35)
    .sort((a, b) => b.modelProbability - a.modelProbability || closeness(a) - closeness(b))
    .slice(0, 60)
    .forEach((c) => chosen.set(c, true));
  return [...chosen.keys()].sort(byProbability);
}

export interface RiskThresholds {
  prudent: number;
  equilibre: number;
}

export function riskLevel(combinedProbability: number, t: RiskThresholds): "prudent" | "equilibre" | "audacieux" {
  if (combinedProbability >= t.prudent) return "prudent";
  if (combinedProbability >= t.equilibre) return "equilibre";
  return "audacieux";
}

/** État réel d'une sélection au moment du contrôle (relu en base). */
export interface LiveCheck {
  matchExists: boolean;
  status: string | null;
  kickoffAt: string | null;
  /** Cote médiane actuelle de l'issue (null si l'issue n'est plus cotée). */
  currentOdd: number | null;
  oddsCapturedAt: string | null;
}

/**
 * Contrôle qualité (prompt §7.5) : existence et statut du match, heure de début, marché
 * et cote disponibles et récents, incompatibilités, doublons, cote totale cohérente.
 * Renvoie la liste des motifs de refus (vide = coupon conforme).
 */
export function qualityCheck(
  coupon: ProposedCoupon,
  live: Map<string, LiveCheck>,
  criteria: Criteria,
  now: Date,
  takenFingerprints: Set<string>,
): string[] {
  const reasons: string[] = [];
  const t = now.getTime();
  const n = coupon.selections.length;
  if (n < criteria.min_selections || n > criteria.max_selections) reasons.push(`nombre de sélections (${n}) hors critères`);
  if (new Set(coupon.selections.map((s) => s.matchId)).size !== n) reasons.push("deux sélections du même match");
  if (takenFingerprints.has(coupon.fingerprint)) reasons.push("coupon identique déjà en circulation");
  const recomputed = totalOddOf(coupon.selections);
  if (Math.abs(recomputed - coupon.totalOdd) > 0.011) reasons.push("cote totale incohérente");
  if (recomputed < criteria.min_total_odd - 0.005 || recomputed > criteria.max_total_odd + 0.005) {
    reasons.push(`cote totale ${recomputed} hors fourchette`);
  }
  for (const s of coupon.selections) {
    const label = `${s.home} – ${s.away}`;
    const l = live.get(`${s.matchId}:${s.key}`);
    if (!l || !l.matchExists) {
      reasons.push(`${label} : match introuvable`);
      continue;
    }
    if (l.status !== "scheduled") reasons.push(`${label} : match ${l.status ?? "au statut inconnu"}`);
    if (!l.kickoffAt || Date.parse(l.kickoffAt) - t < criteria.min_minutes_before_kickoff * 60_000) {
      reasons.push(`${label} : coup d'envoi trop proche ou passé`);
    }
    if (l.currentOdd === null) reasons.push(`${label} : issue ${s.key} plus cotée`);
    else if (!l.oddsCapturedAt || t - Date.parse(l.oddsCapturedAt) > criteria.max_odds_age_hours * HOUR) {
      reasons.push(`${label} : cote trop ancienne`);
    }
  }
  return reasons;
}

// ---------------------------------------------------------------------------
// Textes calculés (sans IA) : traçables, uniquement à partir des données.
// ---------------------------------------------------------------------------
const pct = (p: number) => `${Math.round(p * 100)} %`;
const dec = (x: number, d = 2) => x.toFixed(d).replace(".", ",");

export function outcomeLabel(key: string, home: string, away: string): string {
  const [market, outcome, ...rest] = key.split(".");
  const line = rest.join(".").replace(".", ",");
  if (market === "1X2") return outcome === "HOME" ? `Victoire ${home}` : outcome === "AWAY" ? `Victoire ${away}` : "Match nul";
  if (market === "DC") return outcome === "1X" ? `${home} ou nul` : outcome === "X2" ? `Nul ou ${away}` : `${home} ou ${away}`;
  if (market === "OU") return `${outcome === "OVER" ? "Plus" : "Moins"} de ${line} buts`;
  if (market === "BTTS") return outcome === "YES" ? "Les deux équipes marquent" : "Au moins une équipe ne marque pas";
  if (market === "DNB") return `${outcome === "HOME" ? home : away} (remboursé si nul)`;
  if (market === "TTH" || market === "TTA") {
    return `${market === "TTH" ? home : away} : ${outcome === "OVER" ? "plus" : "moins"} de ${line} but${line === "0,5" ? "" : "s"}`;
  }
  return key;
}

interface FicheFacts {
  model: { expected_goals_home: number; expected_goals_away: number };
  teams: {
    home: { form: string; standing: { rank: number } | null };
    away: { form: string; standing: { rank: number } | null };
  };
}

/** Justification factuelle d'une sélection, tirée de la fiche du moteur. */
export function justificationFor(
  c: Pick<Candidate, "modelProbability" | "impliedProbability" | "edge" | "home" | "away">,
  fiche: FicheFacts,
): string {
  const parts = [`Modèle : ${pct(c.modelProbability)}`];
  if (c.impliedProbability !== null && c.edge !== null) {
    const pts = Math.round(c.edge * 100);
    parts[0] += ` contre ${pct(c.impliedProbability)} pour le marché (écart ${pts >= 0 ? "+" : "−"}${Math.abs(pts)} pts)`;
  }
  parts.push(`buts attendus ${dec(fiche.model.expected_goals_home)} – ${dec(fiche.model.expected_goals_away)}`);
  const form = [
    fiche.teams.home.form ? `${c.home} ${fiche.teams.home.form}` : "",
    fiche.teams.away.form ? `${c.away} ${fiche.teams.away.form}` : "",
  ].filter(Boolean);
  if (form.length) parts.push(`forme (V/N/D, du plus récent) : ${form.join(", ")}`);
  const hr = fiche.teams.home.standing?.rank;
  const ar = fiche.teams.away.standing?.rank;
  if (hr && ar) parts.push(`classement : ${hr}e contre ${ar}e`);
  return parts.join(" ; ") + ".";
}

/** Analyse générale calculée (repli si l'IA est indisponible ou refusée). */
export function defaultSummary(coupon: ProposedCoupon): { analyse_generale: string; points_de_vigilance: string[] } {
  const byP = [...coupon.selections].sort((a, b) => b.modelProbability - a.modelProbability);
  const strongest = byP[0];
  const weakest = byP.at(-1)!;
  const label = (s: Candidate) => `${outcomeLabel(s.key, s.home, s.away)} (${s.home} – ${s.away}, ${pct(s.modelProbability)})`;
  const text = [
    `${coupon.selections.length} sélections pour une cote totale de ${dec(coupon.totalOdd)}.`,
    `Probabilité combinée estimée : ${pct(coupon.combinedProbability)}` +
    (coupon.impliedProbability !== null ? ` (marché : ${pct(coupon.impliedProbability)}).` : "."),
    coupon.selections.length > 1
      ? `Sélection la plus solide : ${label(strongest)} ; la plus fragile : ${label(weakest)}.`
      : "",
  ].filter(Boolean).join(" ");
  return {
    analyse_generale: text,
    points_de_vigilance: [
      "La probabilité combinée suppose des matchs indépendants : c'est une estimation.",
      "Compositions, blessures et suspensions ne sont pas prises en compte.",
    ],
  };
}

export const CATEGORY_TITLES: Record<string, string> = {
  du_jour: "Coupon du jour",
  prudent: "Coupon prudent",
  equilibre: "Coupon équilibré",
  audacieux: "Coupon audacieux",
  cote_elevee: "Coupon cote élevée",
  multi_competitions: "Coupon multi-compétitions",
  competition: "Coupon spécial compétition",
  marche: "Coupon spécial marché",
  strategie: "Coupon stratégie",
};

/**
 * Nombre maximal de coupons d'une catégorie pour un même jour de match.
 * Le « Coupon du jour » est unique par jour, quelle que soit la façon dont il est généré
 * (créneau, génération continue ou à la demande). 0 = pas de limite.
 */
export function dailyLimit(category: string, criteria: Criteria): number {
  if (criteria.max_per_day !== null) return criteria.max_per_day;
  return category === "du_jour" ? 1 : 0;
}
