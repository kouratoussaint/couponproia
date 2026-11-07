// Compréhension d'une demande de l'utilisateur : l'IA traduit le langage naturel en une
// intention et des critères structurés ; ce module les vérifie, les borne et les convertit
// en critères du générateur. Tout le reste (sélections, cotes, contrôles) est calculé.
import { type Criteria, DEFAULT_CRITERIA, parseCriteria } from "../coupons/generator.ts";
import { tzOffsetMs } from "../coupons/schedule.ts";

export const INTENTS = [
  "creer_coupon",
  "variantes",
  "modifier_coupon",
  "analyser_coupon",
  "analyser_matchs",
  "question",
] as const;
export type IntentKind = typeof INTENTS[number];

/** Intentions payantes (une action réussie = un débit). Les questions sont gratuites. */
export const PAID_INTENTS: IntentKind[] = ["creer_coupon", "variantes", "modifier_coupon", "analyser_coupon", "analyser_matchs"];

export interface Intent {
  intent: IntentKind;
  jour: string | null;
  competitions: string[];
  equipes: string[];
  exclure_equipes: string[];
  nombre_selections: number | null;
  cote_totale_cible: number | null;
  cote_totale_min: number | null;
  cote_totale_max: number | null;
  cote_selection_min: number | null;
  cote_selection_max: number | null;
  marches: string[];
  issues: string[];
  risque: "prudent" | "modere" | "audacieux" | null;
  nombre_coupons: number | null;
  retirer_positions: number[];
  remplacer_plus_fragiles: number;
  ajouter: number;
  reponse: string;
}

const MARKETS = ["1X2", "DC", "OU", "BTTS", "DNB", "TTH", "TTA"];
const KEY_RE =
  /^(1X2\.(HOME|DRAW|AWAY)|DC\.(1X|12|X2)|OU\.(OVER|UNDER)\.[0-3]\.5|BTTS\.(YES|NO)|DNB\.(HOME|AWAY)|TT[HA]\.(OVER|UNDER)\.[0-2]\.5)$/;

function num(v: unknown, lo: number, hi: number): number | null {
  if (v === null || v === undefined || v === "") return null;
  const x = Number(String(v).replace(",", "."));
  return Number.isFinite(x) ? Math.min(hi, Math.max(lo, x)) : null;
}
function strings(v: unknown, max = 10): string[] {
  return Array.isArray(v) ? v.map((x) => String(x).trim()).filter(Boolean).slice(0, max) : [];
}

/** Valide la réponse de l'IA ; les valeurs hors bornes sont ramenées dans des limites raisonnables. */
export function parseIntent(raw: unknown): { ok: true; value: Intent } | { ok: false; errors: string[] } {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return { ok: false, errors: ["Objet JSON attendu."] };
  const r = raw as Record<string, unknown>;
  const c = (r.criteres && typeof r.criteres === "object" ? r.criteres : {}) as Record<string, unknown>;
  const m = (r.modification && typeof r.modification === "object" ? r.modification : {}) as Record<string, unknown>;
  const intent = String(r.intent ?? "");
  if (!(INTENTS as readonly string[]).includes(intent)) return { ok: false, errors: [`« intent » doit valoir : ${INTENTS.join(", ")}.`] };
  const reponse = typeof r.reponse === "string" ? r.reponse.trim().slice(0, 1200) : "";
  if (intent === "question" && !reponse) return { ok: false, errors: ["« reponse » obligatoire pour une question."] };
  const risque = ["prudent", "modere", "audacieux"].includes(String(c.risque)) ? c.risque as Intent["risque"] : null;
  const jour = typeof c.jour === "string" && /^(aujourdhui|demain|week_end|\d{4}-\d{2}-\d{2})$/.test(c.jour) ? c.jour : null;
  return {
    ok: true,
    value: {
      intent: intent as IntentKind,
      jour,
      competitions: strings(c.competitions),
      equipes: strings(c.equipes, 6),
      exclure_equipes: strings(c.exclure_equipes),
      nombre_selections: num(c.nombre_selections, 1, 10) === null ? null : Math.round(num(c.nombre_selections, 1, 10)!),
      cote_totale_cible: num(c.cote_totale_cible, 1.1, 500),
      cote_totale_min: num(c.cote_totale_min, 1.05, 500),
      cote_totale_max: num(c.cote_totale_max, 1.05, 1000),
      cote_selection_min: num(c.cote_selection_min, 1.01, 20),
      cote_selection_max: num(c.cote_selection_max, 1.01, 50),
      marches: strings(c.marches).map((x) => x.toUpperCase()).filter((x) => MARKETS.includes(x)),
      issues: strings(c.issues, 20).map((x) => x.toUpperCase()).filter((x) => KEY_RE.test(x)),
      risque,
      nombre_coupons: num(c.nombre_coupons, 1, 3) === null ? null : Math.round(num(c.nombre_coupons, 1, 3)!),
      retirer_positions: (Array.isArray(m.retirer_positions) ? m.retirer_positions : []).map(Number)
        .filter((x) => Number.isInteger(x) && x >= 1 && x <= 12),
      remplacer_plus_fragiles: Math.round(num(m.remplacer_plus_fragiles, 0, 6) ?? 0),
      ajouter: Math.round(num(m.ajouter, 0, 6) ?? 0),
      reponse,
    },
  };
}

/** Période de matchs demandée, en heure locale. Par défaut : les 48 prochaines heures. */
export function dateRange(
  jour: string | null,
  now: Date,
  timeZone: string,
  lang: "fr" | "en" = "fr",
): { from: Date; until: Date; label: string } {
  const en = lang === "en";
  const offset = tzOffsetMs(now, timeZone);
  const local = new Date(now.getTime() + offset);
  const dayStart = (d: Date) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - offset);
  const addDays = (d: Date, n: number) => new Date(d.getTime() + n * 86400_000);
  const today = dayStart(local);
  if (jour === "aujourdhui") return { from: now, until: addDays(today, 1), label: en ? "today" : "aujourd'hui" };
  if (jour === "demain") return { from: addDays(today, 1), until: addDays(today, 2), label: en ? "tomorrow" : "demain" };
  if (jour === "week_end") {
    const dow = local.getUTCDay(); // 0 dimanche … 6 samedi
    const toSat = dow === 0 ? -1 : 6 - dow;
    const sat = addDays(today, toSat);
    return { from: dow === 6 || dow === 0 ? now : sat, until: addDays(sat, 2), label: en ? "this weekend" : "ce week-end" };
  }
  if (jour && /^\d{4}-\d{2}-\d{2}$/.test(jour)) {
    const d = new Date(Date.parse(`${jour}T00:00:00Z`) - offset);
    return { from: d, until: addDays(d, 1), label: `${en ? "on" : "le"} ${jour.slice(8, 10)}/${jour.slice(5, 7)}` };
  }
  return { from: now, until: new Date(now.getTime() + 48 * 3600_000), label: en ? "in the next 48 hours" : "des 48 prochaines heures" };
}

const RISK = {
  prudent: { min_model_probability: 0.6, max_selection_odd: 1.9, total: [1.5, 3.5] },
  modere: { min_model_probability: 0.45, max_selection_odd: 2.8, total: [3, 8] },
  audacieux: { min_model_probability: 0.33, max_selection_odd: 4.5, total: [8, 30] },
} as const;

/**
 * Critères du générateur pour une demande. `validatedOnly` : marchés non demandés
 * explicitement → seulement ceux où le moteur bat la référence.
 */
export function criteriaFromIntent(
  i: Intent,
  windowHours: number,
  lang: "fr" | "en" = "fr",
): { criteria: Criteria; warnings: string[] } {
  const warnings: string[] = [];
  const risk = i.risque ? RISK[i.risque] : null;
  const marketsAsked = i.marches.length > 0 || i.issues.length > 0;
  const markets = i.marches.length ? [...i.marches] : i.issues.length ? [...new Set(i.issues.map((k) => k.split(".")[0]))] : ["1X2", "DC"];
  if (i.issues.length) for (const k of i.issues) if (!markets.includes(k.split(".")[0])) markets.push(k.split(".")[0]);

  let minTotal = risk ? risk.total[0] : 1.8;
  let maxTotal = risk ? risk.total[1] : 12;
  if (i.cote_totale_cible) {
    minTotal = i.cote_totale_cible * 0.85;
    maxTotal = i.cote_totale_cible * 1.15;
  }
  if (i.cote_totale_min) minTotal = i.cote_totale_min;
  if (i.cote_totale_max) maxTotal = i.cote_totale_max;
  if (maxTotal < minTotal) maxTotal = minTotal * 1.2;

  const n = i.nombre_selections;
  const criteria = parseCriteria({
    ...DEFAULT_CRITERIA,
    min_selections: n ?? 2,
    max_selections: n ?? 6,
    min_total_odd: minTotal,
    max_total_odd: maxTotal,
    min_selection_odd: i.cote_selection_min ?? 1.15,
    max_selection_odd: i.cote_selection_max ?? risk?.max_selection_odd ?? 3.5,
    coupons_per_run: i.intent === "variantes" ? (i.nombre_coupons ?? 3) : 1,
    markets,
    allowed_keys: i.issues,
    min_model_probability: risk?.min_model_probability ?? 0.4,
    min_edge: -0.05,
    max_edge: 0.06,
    min_reliability: "moyenne",
    window_hours: Math.max(1, Math.ceil(windowHours)),
    min_minutes_before_kickoff: 15,
    max_odds_age_hours: 24,
    require_validated_markets: !marketsAsked,
  });
  if (marketsAsked && markets.some((m) => m === "OU" || m === "BTTS")) {
    warnings.push(
      lang === "en"
        ? "On past data, the engine does no better than a simple frequency for goals (over/under, both teams score): treat these probabilities with caution."
        : "Sur l'historique, le moteur ne fait pas mieux qu'une simple fréquence pour les buts (plus/moins, les deux marquent) : ces probabilités sont à prendre avec prudence.",
    );
  }
  if (marketsAsked && markets.some((m) => m === "DNB" || m === "TTH" || m === "TTA")) {
    warnings.push(
      lang === "en"
        ? "Draw no bet and team goals: recent markets, not yet validated by the engine evaluation; treat the probabilities with caution."
        : "Remboursé si nul et buts par équipe : marchés récents, pas encore validés par l'évaluation du moteur ; probabilités à prendre avec prudence.",
    );
  }
  return { criteria, warnings };
}

/** Rapprochement d'un nom saisi avec les noms connus (casse, accents et espaces ignorés). */
export function normalizeName(s: string): string {
  return s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

/** Pays (nom du fournisseur, normalisé) et façons courantes de le dire, en français et en anglais. */
const COUNTRY_WORDS: Record<string, string[]> = {
  "france": ["francais", "francaise"],
  "england": ["angleterre", "anglais", "anglaise", "english"],
  "spain": ["espagne", "espagnol", "espagnole", "spanish"],
  "italy": ["italie", "italien", "italienne", "italian"],
  "germany": ["allemagne", "allemand", "allemande", "german"],
  "ivory coast": ["cote d ivoire", "ivoirien", "ivoirienne", "ivorian", "rci"],
  "burkina faso": ["burkina", "burkinabe"],
  "senegal": ["senegalais", "senegalaise", "senegalese"],
  "algeria": ["algerie", "algerien", "algerienne", "algerian"],
  "tunisia": ["tunisie", "tunisien", "tunisienne", "tunisian"],
  "egypt": ["egypte", "egyptien", "egyptienne", "egyptian"],
  "morocco": ["maroc", "marocain", "marocaine", "moroccan"],
  "ghana": ["ghaneen", "ghaneenne", "ghanaian"],
  "mali": ["malien", "malienne", "malian"],
  "south africa": ["afrique du sud", "sud africain", "sud africaine", "south african"],
  "saudi arabia": ["arabie saoudite", "saoudien", "saoudienne", "saudi"],
  "united arab emirates": ["emirats", "emirati", "emiratie", "uae"],
  "kuwait": ["koweit", "koweitien", "koweitienne", "kuwaiti"],
  "bahrain": ["bahrein", "bahreini", "bahreinie"],
  "qatar": ["qatari", "qatarie"],
  "iraq": ["irak", "irakien", "irakienne", "iraqi"],
  "jordan": ["jordanie", "jordanien", "jordanienne", "jordanian"],
};

function mentionsCountry(text: string, country: string | null | undefined): boolean {
  if (!country) return false;
  const c = normalizeName(country);
  const words = [c, ...(COUNTRY_WORDS[c] ?? [])];
  return words.some((w) => ` ${text} `.includes(` ${w} `));
}

export interface KnownCompetition {
  id: number;
  name: string;
  country?: string | null;
  display_name?: string | null;
  priority?: number;
}

/**
 * Compétitions demandées par leur nom, le pays précisant un nom porté par plusieurs
 * (« Ligue 1 ivoirienne », « Premier League Égypte »). Nom ambigu sans pays : la
 * compétition principale (ordre de la console) est retenue et les autres sont proposées.
 */
export function matchNames(
  wanted: string[],
  known: KnownCompetition[],
): { ids: number[]; unknown: string[]; ambiguous: { asked: string; chosen: string; others: string[] }[] } {
  const ids = new Set<number>();
  const unknown: string[] = [];
  const ambiguous: { asked: string; chosen: string; others: string[] }[] = [];
  const label = (k: KnownCompetition) => k.display_name ?? k.name;
  for (const w of wanted) {
    const nw = normalizeName(w);
    const exact = known.filter((k) => k.display_name && normalizeName(k.display_name) === nw);
    let hits = exact.length ? exact : known.filter((k) => {
      const nk = normalizeName(k.name);
      return nk === nw || nk.includes(nw) || (nw.length >= 4 && nw.includes(nk));
    });
    if (hits.length > 1) {
      const byCountry = hits.filter((k) => mentionsCountry(nw, k.country));
      if (byCountry.length) hits = byCountry;
    }
    // Plusieurs compétitions du même nom, aucun pays précisé : la principale, les autres proposées.
    const sameName = new Set(hits.map((h) => normalizeName(h.name)));
    if (hits.length > 1 && sameName.size === 1) {
      const sorted = [...hits].sort((a, b) => (a.priority ?? 100) - (b.priority ?? 100));
      ambiguous.push({ asked: w, chosen: label(sorted[0]), others: sorted.slice(1).map(label) });
      hits = [sorted[0]];
    }
    if (hits.length) hits.forEach((h) => ids.add(h.id));
    else unknown.push(w);
  }
  return { ids: [...ids], unknown, ambiguous };
}
