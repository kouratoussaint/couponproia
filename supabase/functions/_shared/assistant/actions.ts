// Actions déterministes de l'assistant : analyse d'un coupon (sélections fragiles,
// corrélations, qualité des données) et repérage des meilleures opportunités d'une période.
import { type Candidate, familyOf, outcomeLabel, outcomeLabelEn, qualityFamilyOf } from "../coupons/generator.ts";

const pct = (p: number) => `${Math.round(p * 100)} %`;
const pctEn = (p: number) => `${Math.round(p * 100)}%`;
const RELIABILITY_EN: Record<string, string> = { faible: "low", moyenne: "medium", bonne: "good" };

export interface CouponLine {
  position: number;
  matchId: number;
  home: string;
  away: string;
  competition: string;
  kickoffAt: string;
  key: string;
  odd: number;
  modelProbability: number;
  impliedProbability: number | null;
  edge: number | null;
  reliability: "faible" | "moyenne" | "bonne";
  /** Statut et cote actuels relus en base. */
  status?: string;
  currentOdd?: number | null;
}

const RELIABILITY_PENALTY = { faible: 0.1, moyenne: 0.04, bonne: 0 };

/** Score de fragilité : plus il est élevé, plus la sélection est fragile. */
export function fragility(l: CouponLine): number {
  return (1 - l.modelProbability) + RELIABILITY_PENALTY[l.reliability] + Math.max(0, -(l.edge ?? 0));
}

export interface CouponDiagnosis {
  total_odd: number;
  combined_probability: number;
  implied_probability: number | null;
  fragiles: { position: number; selection: string; raison: string }[];
  alertes: string[];
  qualite: string[];
}

export function diagnoseCoupon(
  lines: CouponLine[],
  beatsBaseline: Record<string, boolean> | null,
  now: Date,
  lang: "fr" | "en" = "fr",
): CouponDiagnosis {
  if (lang === "en") return diagnoseCouponEn(lines, beatsBaseline, now);
  const total = Math.round(lines.reduce((p, l) => p * l.odd, 1) * 100) / 100;
  const combined = Math.round(lines.reduce((p, l) => p * l.modelProbability, 1) * 10000) / 10000;
  const implied = lines.every((l) => l.impliedProbability !== null)
    ? Math.round(lines.reduce((p, l) => p * (l.impliedProbability as number), 1) * 10000) / 10000
    : null;
  const sorted = [...lines].sort((a, b) => fragility(b) - fragility(a));
  const fragiles = sorted.slice(0, Math.min(2, Math.max(1, Math.floor(lines.length / 2)))).map((l) => {
    const reasons = [`probabilité du modèle ${pct(l.modelProbability)}`];
    if (l.reliability !== "bonne") reasons.push(`fiabilité ${l.reliability}`);
    if (l.edge !== null && l.edge < 0) reasons.push(`le marché est plus optimiste que le modèle (${Math.round(l.edge * 100)} pts)`);
    return { position: l.position, selection: `${outcomeLabel(l.key, l.home, l.away)} (${l.home} – ${l.away})`, raison: reasons.join(", ") };
  });

  const alertes: string[] = [];
  for (const l of lines) {
    if (l.status && l.status !== "scheduled") alertes.push(`${l.home} – ${l.away} : match ${l.status}.`);
    else if (Date.parse(l.kickoffAt) <= now.getTime()) alertes.push(`${l.home} – ${l.away} : le match a commencé.`);
    if (l.currentOdd === null) alertes.push(`${l.home} – ${l.away} : l'issue n'est plus cotée.`);
    else if (l.currentOdd !== undefined && Math.abs(l.currentOdd - l.odd) >= 0.05) {
      alertes.push(`${l.home} – ${l.away} : la cote est passée de ${l.odd.toFixed(2).replace(".", ",")} à ${l.currentOdd.toFixed(2).replace(".", ",")}.`);
    }
  }
  const byCompetition = new Map<string, number>();
  for (const l of lines) byCompetition.set(l.competition, (byCompetition.get(l.competition) ?? 0) + 1);
  const concentrated = [...byCompetition].filter(([, n]) => n >= 3);
  const qualite: string[] = [];
  if (concentrated.length) {
    qualite.push(`${concentrated.map(([c, n]) => `${n} sélections en ${c}`).join(", ")} : résultats possiblement liés (même journée, mêmes tendances).`);
  }
  const weakMarkets = [...new Set(lines.map((l) => qualityFamilyOf(l.key)))].filter((f) => beatsBaseline?.[f] === false);
  if (weakMarkets.length) {
    qualite.push(`Marchés ${weakMarkets.join(", ")} : sur l'historique, le moteur n'y fait pas mieux qu'une simple fréquence.`);
  }
  const lowReliability = lines.filter((l) => l.reliability === "faible").length;
  if (lowReliability) qualite.push(`${lowReliability} sélection(s) à fiabilité faible (peu de matchs joués).`);
  qualite.push("Compositions, blessures et suspensions ne sont pas prises en compte.");
  return { total_odd: total, combined_probability: combined, implied_probability: implied, fragiles, alertes, qualite };
}

export interface Opportunity {
  match_id: number;
  match: string;
  competition: string;
  kickoff_at: string;
  selection: string;
  key: string;
  odd: number;
  model_probability: number;
  implied_probability: number | null;
  edge: number | null;
  reliability: string;
}

/** Meilleure issue de chaque match (probabilité du modèle, écart raisonnable), triées. */
export function opportunities(cands: Candidate[], limit = 8, lang: "fr" | "en" = "fr"): Opportunity[] {
  const best = new Map<number, Candidate>();
  for (const c of cands) {
    const b = best.get(c.matchId);
    if (!b || c.modelProbability * (1 + (c.edge ?? 0)) > b.modelProbability * (1 + (b.edge ?? 0))) best.set(c.matchId, c);
  }
  return [...best.values()]
    .sort((a, b) => (b.edge ?? 0) - (a.edge ?? 0) || b.modelProbability - a.modelProbability)
    .slice(0, limit)
    .map((c) => ({
      match_id: c.matchId,
      match: `${c.home} – ${c.away}`,
      competition: c.competitionName,
      kickoff_at: c.kickoffAt,
      selection: lang === "en" ? outcomeLabelEn(c.key, c.home, c.away) : outcomeLabel(c.key, c.home, c.away),
      key: c.key,
      odd: c.odd,
      model_probability: c.modelProbability,
      implied_probability: c.impliedProbability,
      edge: c.edge,
      reliability: c.reliability,
    }));
}

function diagnoseCouponEn(lines: CouponLine[], beatsBaseline: Record<string, boolean> | null, now: Date): CouponDiagnosis {
  const total = Math.round(lines.reduce((p, l) => p * l.odd, 1) * 100) / 100;
  const combined = Math.round(lines.reduce((p, l) => p * l.modelProbability, 1) * 10000) / 10000;
  const implied = lines.every((l) => l.impliedProbability !== null)
    ? Math.round(lines.reduce((p, l) => p * (l.impliedProbability as number), 1) * 10000) / 10000
    : null;
  const sorted = [...lines].sort((a, b) => fragility(b) - fragility(a));
  const fragiles = sorted.slice(0, Math.min(2, Math.max(1, Math.floor(lines.length / 2)))).map((l) => {
    const reasons = [`model probability ${pctEn(l.modelProbability)}`];
    if (l.reliability !== "bonne") reasons.push(`${RELIABILITY_EN[l.reliability]} reliability`);
    if (l.edge !== null && l.edge < 0) reasons.push(`the market is more optimistic than the model (${Math.round(l.edge * 100)} pts)`);
    return { position: l.position, selection: `${outcomeLabelEn(l.key, l.home, l.away)} (${l.home} – ${l.away})`, raison: reasons.join(", ") };
  });

  const alertes: string[] = [];
  for (const l of lines) {
    if (l.status && l.status !== "scheduled") alertes.push(`${l.home} – ${l.away}: match ${l.status}.`);
    else if (Date.parse(l.kickoffAt) <= now.getTime()) alertes.push(`${l.home} – ${l.away}: the match has started.`);
    if (l.currentOdd === null) alertes.push(`${l.home} – ${l.away}: the outcome is no longer priced.`);
    else if (l.currentOdd !== undefined && Math.abs(l.currentOdd - l.odd) >= 0.05) {
      alertes.push(`${l.home} – ${l.away}: the odd moved from ${l.odd.toFixed(2)} to ${l.currentOdd.toFixed(2)}.`);
    }
  }
  const byCompetition = new Map<string, number>();
  for (const l of lines) byCompetition.set(l.competition, (byCompetition.get(l.competition) ?? 0) + 1);
  const concentrated = [...byCompetition].filter(([, n]) => n >= 3);
  const qualite: string[] = [];
  if (concentrated.length) {
    qualite.push(`${concentrated.map(([c, n]) => `${n} selections in ${c}`).join(", ")}: results possibly linked (same matchday, same trends).`);
  }
  const weakMarkets = [...new Set(lines.map((l) => qualityFamilyOf(l.key)))].filter((f) => beatsBaseline?.[f] === false);
  if (weakMarkets.length) {
    qualite.push(`Markets ${weakMarkets.join(", ")}: on past data, the engine does no better than a simple frequency.`);
  }
  const lowReliability = lines.filter((l) => l.reliability === "faible").length;
  if (lowReliability) qualite.push(`${lowReliability} selection(s) with low reliability (few matches played).`);
  qualite.push("Line-ups, injuries and suspensions are not taken into account.");
  return { total_odd: total, combined_probability: combined, implied_probability: implied, fragiles, alertes, qualite };
}

/** Motifs d'exclusion du moteur, en anglais (assistant et laboratoire en anglais). */
export const EXCLUSION_EN: Record<string, string> = {
  "coup d'envoi trop proche": "kick-off too close",
  "hors fenêtre de matchs": "outside the match window",
  "compétition non retenue": "competition not selected",
  "marché non retenu": "market not selected",
  "issue non demandée": "outcome not requested",
  "marché non validé par l'évaluation du moteur": "market not validated by the engine evaluation",
  "compétition où le moteur ne bat pas la référence": "competition where the engine does not beat the baseline",
  "cote trop ancienne": "odd too old",
  "cote hors fourchette": "odd out of range",
  "probabilité du modèle trop faible": "model probability too low",
  "écart avec le marché insuffisant": "edge with the market too small",
  "désaccord trop fort avec le marché": "disagreement with the market too strong",
  "fiabilité insuffisante": "reliability too low",
};
export const exclusionLabel = (reason: string, lang: "fr" | "en") => (lang === "en" ? EXCLUSION_EN[reason] ?? reason : reason);

export { familyOf };
