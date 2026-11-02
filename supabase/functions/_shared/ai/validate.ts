// Garde-fous de l'analyse IA. Une réponse n'est publiée que si :
//  - elle respecte la structure attendue ;
//  - chaque marché cité existe dans la fiche, avec la probabilité du modèle (± 2 points) ;
//  - chaque nombre écrit figure dans la fiche (pas de statistique inventée) ;
//  - aucun mot de certitude n'est employé (« sûr », « garanti »…).
// Sinon on redemande une fois en listant les erreurs, puis on se replie sur la fiche seule.

export interface MarketPick {
  cle: string;
  probabilite_modele: number;
  justification: string;
  cote_mediane?: number | null;
  probabilite_implicite?: number | null;
  ecart?: number | null;
}

export interface Analysis {
  resume: string;
  forme: string;
  facteurs_domicile: string[];
  facteurs_exterieur: string[];
  tendances: string[];
  marches_envisageables: MarketPick[];
  risques: string[];
  informations_manquantes: string[];
  conclusion: string;
  recommandation_possible: boolean;
}

/** Ce que la validation doit connaître de la fiche. */
export interface FicheLike {
  reliability: string;
  model: { probabilities: Record<string, number> };
  market: { lines: { key: string; odd_median: number; implied_probability: number | null; edge: number | null }[] };
  engine_quality?: { beats_baseline: Record<string, boolean> } | null;
}

const qualityGroupOf = (key: string) => (key.startsWith("DC.") ? "1X2" : key.split(".")[0]);

/** Indices qu'une justification s'appuie sur la fiche, pas seulement sur la probabilité. */
const GROUNDING =
  /forme|domicile|extérieur|buts? attendus?|classement|points?|confrontation|série|encaiss|marqu|bilan|cote|marché|écart|défense|attaque|moyenne|form|home|away|expected goals|standing|table|head-to-head|streak|conced|scor|record|odds?|market|edge|defen[cs]e|attack|average/iu;

/** Une justification qui se contente de répéter la probabilité n'apporte rien. */
export function isGrounded(justification: string): boolean {
  return justification.trim().length >= 40 && GROUNDING.test(justification);
}

const STRING_FIELDS = ["resume", "forme", "conclusion"] as const;
const LIST_FIELDS = ["facteurs_domicile", "facteurs_exterieur", "tendances", "risques", "informations_manquantes"] as const;
const MAX_ITEMS = 4;

const L = String.raw`(?<![\p{L}\p{N}])`;
const R = String.raw`(?![\p{L}\p{N}])`;
export const FORBIDDEN = new RegExp(
  [
    "sûr(e|s|es)?",
    "sûrement",
    "garanti(e|es|s|r|t)?",
    "assuré(e|s|es)?",
    "certitudes?",
    "imparables?",
    "infaillibles?",
    "sans risque",
    "gains?",
    // Anglais (analyses demandées en anglais).
    "guaranteed?",
    "guarantees",
    "sure (?:bets?|wins?|thing)",
    "surely",
    "certaint(?:y|ies)",
    "unbeatable",
    "infallible",
    "risk[- ]free",
    "winnings",
    "can'?t lose",
  ].map((w) => `${L}${w}${R}`).join("|") + String.raw`|${L}100\s?%`,
  "iu",
);

/** Extrait l'objet JSON d'une réponse (tolère un bloc ```json … ``` ou du texte autour). */
export function parseJsonLoose(text: string): unknown {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("aucun objet JSON");
  return JSON.parse(text.slice(start, end + 1));
}

/** Tous les nombres présents dans la fiche (valeurs, dates, scores…), et les pourcentages des probabilités. */
export function allowedNumbers(fiche: unknown): number[] {
  const out = new Set<number>();
  const text = JSON.stringify(fiche);
  for (const m of text.matchAll(/\d+(?:\.\d+)?/g)) {
    const v = parseFloat(m[0]);
    out.add(v);
    if (v > 0 && v < 1) out.add(v * 100);
  }
  return [...out];
}

/** Nombres écrits par l'IA qui ne correspondent à rien dans la fiche. */
export function unknownNumbers(text: string, allowed: number[]): string[] {
  const bad: string[] = [];
  for (const m of text.matchAll(/(\d+(?:[.,]\d+)?)(\s*%)?/g)) {
    const raw = m[1];
    const x = parseFloat(raw.replace(",", "."));
    const isPercent = Boolean(m[2]);
    const isInteger = !/[.,]/.test(raw);
    if (isInteger && !isPercent && x <= 10) continue; // petits comptes (« 3 derniers matchs »), scores
    if (isInteger && x >= 1990 && x <= 2100) continue; // années
    const tol = isPercent ? 1.01 : isInteger ? 0.5 : 0.051;
    if (!allowed.some((a) => Math.abs(a - x) <= tol)) bad.push(m[0].trim());
  }
  return bad;
}

const isStringList = (v: unknown): v is string[] => Array.isArray(v) && v.every((s) => typeof s === "string");

export type ValidationResult = { ok: true; analysis: Analysis } | { ok: false; errors: string[] };

export function validateAnalysis(raw: unknown, fiche: FicheLike): ValidationResult {
  const errors: string[] = [];
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return { ok: false, errors: ["La réponse n'est pas un objet JSON."] };
  const r = raw as Record<string, unknown>;

  for (const f of STRING_FIELDS) {
    if (typeof r[f] !== "string" || !(r[f] as string).trim()) errors.push(`Champ « ${f} » manquant ou vide.`);
  }
  for (const f of LIST_FIELDS) {
    if (!isStringList(r[f])) errors.push(`Champ « ${f} » : liste de textes attendue.`);
  }
  if (typeof r.recommandation_possible !== "boolean") errors.push("Champ « recommandation_possible » : booléen attendu.");
  if (!Array.isArray(r.marches_envisageables)) errors.push("Champ « marches_envisageables » : liste attendue.");
  if (errors.length) return { ok: false, errors };

  const probs = fiche.model.probabilities;
  const lines = new Map(fiche.market.lines.map((l) => [l.key, l] as [string, typeof l]));
  const picks: MarketPick[] = [];
  const families = new Map<string, string>();
  for (const item of (r.marches_envisageables as unknown[]).slice(0, 3)) {
    const p = item as Record<string, unknown>;
    const key = String(p?.cle ?? "");
    if (!(key in probs)) {
      errors.push(`Marché « ${key} » absent de model.probabilities.`);
      continue;
    }
    const given = Number(p.probabilite_modele);
    if (!Number.isFinite(given) || Math.abs(given - probs[key]) > 0.02) {
      errors.push(`Marché « ${key} » : probabilité ${p.probabilite_modele} au lieu de ${probs[key]}.`);
      continue;
    }
    if (fiche.engine_quality?.beats_baseline?.[qualityGroupOf(key)] === false) {
      errors.push(
        `Marché « ${key} » : sur l'historique, le moteur ne fait pas mieux qu'une simple fréquence pour ce type de marché. Ne le propose pas.`,
      );
      continue;
    }
    const family = qualityGroupOf(key);
    const previous = families.get(family);
    if (previous) {
      errors.push(
        `« ${previous} » et « ${key} » portent sur le même marché : une seule issue par marché. Garde la mieux étayée.`,
      );
      continue;
    }
    if (typeof p.justification !== "string" || !isGrounded(p.justification)) {
      errors.push(
        `Marché « ${key} » : la justification doit s'appuyer sur un élément de la fiche (forme, bilan domicile/extérieur, buts attendus, classement, confrontations, cote) et pas seulement répéter la probabilité.`,
      );
      continue;
    }
    families.set(family, key);
    const line = lines.get(key);
    picks.push({
      cle: key,
      probabilite_modele: probs[key], // valeur exacte du moteur, jamais celle de l'IA
      justification: p.justification.trim(),
      cote_mediane: line?.odd_median ?? null,
      probabilite_implicite: line?.implied_probability ?? null,
      ecart: line?.edge ?? null,
    });
  }

  const analysis: Analysis = {
    resume: (r.resume as string).trim(),
    forme: (r.forme as string).trim(),
    facteurs_domicile: (r.facteurs_domicile as string[]).slice(0, MAX_ITEMS),
    facteurs_exterieur: (r.facteurs_exterieur as string[]).slice(0, MAX_ITEMS),
    tendances: (r.tendances as string[]).slice(0, MAX_ITEMS),
    marches_envisageables: picks,
    risques: (r.risques as string[]).slice(0, MAX_ITEMS),
    informations_manquantes: (r.informations_manquantes as string[]).slice(0, MAX_ITEMS),
    conclusion: (r.conclusion as string).trim(),
    // Jamais de recommandation sur une estimation fragile, quoi qu'en dise l'IA.
    recommandation_possible: (r.recommandation_possible as boolean) && fiche.reliability !== "faible" &&
      picks.length > 0,
  };

  const texts = [
    analysis.resume,
    analysis.forme,
    analysis.conclusion,
    ...analysis.facteurs_domicile,
    ...analysis.facteurs_exterieur,
    ...analysis.tendances,
    ...analysis.risques,
    ...analysis.informations_manquantes,
    ...picks.map((p) => p.justification),
  ];
  const allText = texts.join("\n");
  const forbidden = allText.match(FORBIDDEN);
  if (forbidden) errors.push(`Mot interdit : « ${forbidden[0]} ». Ce sont des estimations.`);
  const unknown = unknownNumbers(allText, allowedNumbers(fiche));
  if (unknown.length) {
    errors.push(`Nombres absents de la fiche : ${[...new Set(unknown)].slice(0, 6).join(", ")}. N'écris que des valeurs de la fiche.`);
  }

  return errors.length ? { ok: false, errors } : { ok: true, analysis };
}

export interface CouponSummary {
  analyse_generale: string;
  points_de_vigilance: string[];
}

/** Analyse générale d'un coupon : structure, chiffres présents dans la fiche, aucun mot de certitude. */
export function validateCouponSummary(raw: unknown, fiche: unknown): { ok: true; value: CouponSummary } | { ok: false; errors: string[] } {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return { ok: false, errors: ["La réponse n'est pas un objet JSON."] };
  const r = raw as Record<string, unknown>;
  const errors: string[] = [];
  if (typeof r.analyse_generale !== "string" || r.analyse_generale.trim().length < 20) {
    errors.push("Champ « analyse_generale » manquant ou trop court.");
  }
  if (!isStringList(r.points_de_vigilance)) errors.push("Champ « points_de_vigilance » : liste de textes attendue.");
  if (errors.length) return { ok: false, errors };
  const value: CouponSummary = {
    analyse_generale: (r.analyse_generale as string).trim(),
    points_de_vigilance: (r.points_de_vigilance as string[]).map((s) => s.trim()).filter(Boolean).slice(0, 4),
  };
  const text = [value.analyse_generale, ...value.points_de_vigilance].join("\n");
  const forbidden = text.match(FORBIDDEN);
  if (forbidden) errors.push(`Mot interdit : « ${forbidden[0]} ». Ce sont des estimations.`);
  const unknown = unknownNumbers(text, allowedNumbers(fiche));
  if (unknown.length) errors.push(`Nombres absents de la fiche : ${[...new Set(unknown)].slice(0, 6).join(", ")}.`);
  return errors.length ? { ok: false, errors } : { ok: true, value };
}
