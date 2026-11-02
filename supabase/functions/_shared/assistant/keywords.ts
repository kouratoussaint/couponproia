// Lecture déterministe des mots-clés et des chiffres d'une demande (sans IA).
// Les chiffres écrits par l'utilisateur font foi : ils remplacent ceux compris par l'IA, et une
// valeur que l'IA aurait ajoutée sans qu'elle figure dans le message est ignorée.
import type { Intent } from "./intent.ts";
import { tzOffsetMs } from "../coupons/schedule.ts";

export interface Extracted {
  nombre_selections: number | null;
  nombre_coupons: number | null;
  cote_totale_cible: number | null;
  cote_totale_min: number | null;
  cote_totale_max: number | null;
  cote_selection_min: number | null;
  cote_selection_max: number | null;
  jour: string | null;
  marches: string[];
  issues: string[];
  risque: Intent["risque"];
  /** Tous les nombres écrits dans le message (chiffres et nombres en lettres). */
  numbers: number[];
  /** Le message parle-t-il d'un marché (victoire, nul, double chance, buts…) ? */
  mentionsMarket: boolean;
  /** Le message parle-t-il d'un jour ? */
  mentionsDay: boolean;
}

const WORDS: Record<string, number> = {
  un: 1, une: 1, deux: 2, trois: 3, quatre: 4, cinq: 5, six: 6, sept: 7, huit: 8, neuf: 9, dix: 10,
  // Anglais (application réglée sur English).
  one: 1, two: 2, three: 3, four: 4, five: 5, seven: 7, eight: 8, nine: 9, ten: 10,
};
const NUM = `(\\d+(?:\\.\\d+)?|${Object.keys(WORDS).join("|")})`;
const toNum = (s: string) => WORDS[s] ?? Number(s);
const WEEKDAYS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];
const WEEKDAYS_EN = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

/** Minuscules, sans accents, virgule décimale → point, apostrophes simplifiées. */
export function normalizeText(s: string): string {
  return s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase()
    .replace(/[’`]/g, "'").replace(/(\d),(\d)/g, "$1.$2").replace(/\s+/g, " ").trim();
}

function localIso(now: Date, timeZone: string, addDays: number): string {
  const d = new Date(now.getTime() + tzOffsetMs(now, timeZone) + addDays * 86400_000);
  return d.toISOString().slice(0, 10);
}

/** Ligne de buts : « plus de 2 buts » = plus de 2,5 ; « moins de 3 buts » = moins de 2,5. */
function goalLine(n: number, over: boolean): number | null {
  const line = Number.isInteger(n) ? (over ? n + 0.5 : n - 0.5) : n;
  return [0.5, 1.5, 2.5, 3.5].includes(line) ? line : null;
}

export function extractConstraints(message: string, now: Date, timeZone: string): Extracted {
  const t = normalizeText(message);
  const out: Extracted = {
    nombre_selections: null,
    nombre_coupons: null,
    cote_totale_cible: null,
    cote_totale_min: null,
    cote_totale_max: null,
    cote_selection_min: null,
    cote_selection_max: null,
    jour: null,
    marches: [],
    issues: [],
    risque: null,
    numbers: [],
    mentionsMarket: false,
    mentionsDay: false,
  };
  for (const m of t.matchAll(new RegExp(`(?<![\\w.])${NUM}(?![\\w.])`, "g"))) out.numbers.push(toNum(m[1]));

  // Nombre de sélections et de coupons.
  const sel = new RegExp(`${NUM}\\s*(?:matchs?|matches|selections?|paris|evenements?|rencontres?|equipes?|jeux|games?|picks?|legs?|fixtures?|teams?)\\b`).exec(t);
  if (sel) out.nombre_selections = toNum(sel[1]);
  const cps = new RegExp(`${NUM}\\s*(?:coupons?|versions?|variantes?|variants?|propositions?|tickets?|slips?|options?)\\b`).exec(t);
  if (cps && toNum(cps[1]) > 1) out.nombre_coupons = toNum(cps[1]);

  // Cotes par sélection (« cote par match », « chaque match à 1,5 »…).
  const PER = "(?:par|pour chaque|de chaque|chaque|per|for each|each)\\s*(?:match|selection|pari|rencontre|game|pick|leg)";
  const ODD = "(?:cotes?|odds?)";
  const AND = "(?:et|a|-|and|to)";
  const MIN = "(?:d'?au moins|minimum|min|superieures? a|superieure? a|plus de|au dela de|at least|more than|above|over|>=?)";
  const MAX = "(?:maximum|max|d'?au plus|inferieures? a|inferieure? a|moins de|pas plus de|at most|less than|below|under|no more than|up to|<=?)";
  const ABOUT = "(?:de|d'environ|environ|autour de|proche de|vers|a|of|around|about|close to|near|=|:)";
  const perRange = new RegExp(`${ODD}\\s*${PER}\\s*(?:entre|de|between|from)\\s*${NUM}\\s*${AND}\\s*${NUM}`).exec(t);
  const perMin = new RegExp(`${ODD}\\s*${PER}\\s*${MIN}\\s*${NUM}`).exec(t);
  const perMax = new RegExp(`${ODD}\\s*${PER}\\s*${MAX}\\s*${NUM}`).exec(t);
  const perTarget = new RegExp(`${ODD}\\s*${ABOUT}?\\s*${NUM}\\s*${PER}`).exec(t) ??
    new RegExp(`${ODD}\\s*${PER}\\s*${ABOUT}?\\s*${NUM}`).exec(t);
  if (perRange) {
    out.cote_selection_min = Math.min(toNum(perRange[1]), toNum(perRange[2]));
    out.cote_selection_max = Math.max(toNum(perRange[1]), toNum(perRange[2]));
  } else {
    if (perMin) out.cote_selection_min = toNum(perMin[1]);
    if (perMax) out.cote_selection_max = toNum(perMax[1]);
    if (!perMin && !perMax && perTarget) {
      const v = toNum(perTarget[1]);
      out.cote_selection_min = Math.round(v * 0.9 * 100) / 100;
      out.cote_selection_max = Math.round(v * 1.1 * 100) / 100;
    }
  }
  // Cote totale : tout « cote … nombre » qui ne parle pas d'une sélection.
  const S = "(?:[^.?!,;]|\\.(?=\\d))"; // reste de la proposition (un point décimal ne la coupe pas)
  const withoutPer = t.replace(new RegExp(`${ODD}${S}*?${PER}${S}*`, "g"), " ");
  const TOT = "(?:(?:total|overall|combined)\\s*odds?|cotes?\\s*(?:totale?s?|globales?|combinees?|du coupon)?|odds?)";
  const totRange = new RegExp(`${TOT}\\s*(?:entre|de|between|from)\\s*${NUM}\\s*${AND}\\s*${NUM}`).exec(withoutPer);
  const totMin = new RegExp(`${TOT}\\s*${MIN}\\s*${NUM}`).exec(withoutPer);
  const totMax = new RegExp(`${TOT}\\s*${MAX}\\s*${NUM}`).exec(withoutPer);
  if (totRange) {
    out.cote_totale_min = Math.min(toNum(totRange[1]), toNum(totRange[2]));
    out.cote_totale_max = Math.max(toNum(totRange[1]), toNum(totRange[2]));
  } else {
    if (totMin) out.cote_totale_min = toNum(totMin[1]);
    if (totMax) out.cote_totale_max = toNum(totMax[1]);
    if (!totMin && !totMax) {
      const target = new RegExp(`${TOT}\\s*${ABOUT}?\\s*${NUM}`).exec(withoutPer);
      if (target && toNum(target[1]) > 1) out.cote_totale_cible = toNum(target[1]);
    }
  }

  // Jour.
  if (/\bapres[- ]demain\b|\bday after tomorrow\b/.test(t)) out.jour = localIso(now, timeZone, 2);
  else if (/\bdemain\b|\btomorrow\b/.test(t)) out.jour = "demain";
  else if (/\b(aujourd'?hui|ce soir|cet apres-midi|ce matin|today|tonight|this (?:evening|afternoon|morning))\b/.test(t)) {
    out.jour = "aujourdhui";
  }
  else if (/\bweek[- ]?end\b/.test(t)) out.jour = "week_end";
  else {
    const date = /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/.exec(t);
    const wd = new RegExp(`\\b(${[...WEEKDAYS, ...WEEKDAYS_EN].join("|")})\\b`).exec(t);
    if (date) {
      const year = date[3] ? (date[3].length === 2 ? 2000 + Number(date[3]) : Number(date[3])) : Number(localIso(now, timeZone, 0).slice(0, 4));
      const iso = `${year}-${date[2].padStart(2, "0")}-${date[1].padStart(2, "0")}`;
      if (!Number.isNaN(Date.parse(`${iso}T00:00:00Z`))) out.jour = iso;
    } else if (wd) {
      const todayIdx = new Date(Date.parse(`${localIso(now, timeZone, 0)}T12:00:00Z`)).getUTCDay();
      const idx = WEEKDAYS.includes(wd[1]) ? WEEKDAYS.indexOf(wd[1]) : WEEKDAYS_EN.indexOf(wd[1]);
      const delta = (idx - todayIdx + 7) % 7;
      out.jour = localIso(now, timeZone, delta);
    }
  }
  out.mentionsDay = out.jour !== null;

  // Marchés et issues.
  const issues = new Set<string>();
  const markets = new Set<string>();
  if (/double chance/.test(t)) markets.add("DC");
  if (/\b1x2\b|\bvictoires?\b|\bgagnants?\b|\bvainqueurs?\b|\bwins?\b|\bwinners?\b/.test(t)) markets.add("1X2");
  if (/\bmatchs? nuls?\b|\bun nul\b|\ble nul\b|\ba draw\b|\bthe draw\b|\bdraws\b/.test(t)) issues.add("1X2.DRAW");
  for (const m of t.matchAll(new RegExp(`(?:plus de|over|\\+|au moins|more than|at least)\\s*${NUM}\\s*(?:buts?|goals?)`, "g"))) {
    const line = goalLine(toNum(m[1]), true);
    if (line !== null) issues.add(`OU.OVER.${line}`);
  }
  for (const m of t.matchAll(new RegExp(`(?:moins de|under|-|less than|fewer than)\\s*${NUM}\\s*(?:buts?|goals?)`, "g"))) {
    const line = goalLine(toNum(m[1]), false);
    if (line !== null) issues.add(`OU.UNDER.${line}`);
  }
  if (/les deux (?:equipes )?marquent|\bbtts\b|both teams/.test(t)) issues.add("BTTS.YES");
  if (/rembourse(?:e)? si (?:match )?nul|draw no bet|\bdnb\b/.test(t)) markets.add("DNB");
  out.issues = [...issues];
  out.marches = [...markets];
  out.mentionsMarket = markets.size > 0 || issues.size > 0 ||
    /\b(domicile|exterieur|buts?|marque|chance|nul|1x|x2|over|under|goals?|home|away|score|draw|wins?)\b/.test(t);

  // Niveau de risque.
  if (/\b(prudents?|prudence|safe|securises?|peu risques?|faible risque|cautious|careful|low[- ]risk)\b/.test(t)) out.risque = "prudent";
  else if (/\b(audacieux|risques?|grosses? cotes?|gros coup|cotes? elevees?|bold|risky|big odds|high odds)\b/.test(t)) {
    out.risque = "audacieux";
  } else if (/\b(moderes?|equilibres?|moyen|balanced|moderate|medium)\b/.test(t)) out.risque = "modere";
  return out;
}

/** Le nombre figure-t-il dans le message (à 1 % près, pour 1,85 contre 1.85) ? */
const said = (x: number, numbers: number[]) => numbers.some((n) => Math.abs(n - x) <= Math.max(0.01, x * 0.01));

/**
 * Compréhension finale : les chiffres et mots-clés du message priment ; ce que l'IA ajoute sans
 * appui dans le message est retiré (et signalé). Renvoie l'intention corrigée et les corrections.
 */
export function reconcileIntent(ai: Intent, message: string, now: Date, timeZone: string): { intent: Intent; dropped: string[] } {
  const x = extractConstraints(message, now, timeZone);
  const i: Intent = { ...ai };
  const dropped: string[] = [];
  const numeric = [
    "nombre_selections",
    "cote_totale_cible",
    "cote_totale_min",
    "cote_totale_max",
    "cote_selection_min",
    "cote_selection_max",
    "nombre_coupons",
  ] as const;
  for (const k of numeric) {
    const fromText = x[k];
    if (fromText !== null) {
      i[k] = fromText;
    } else if (i[k] !== null && !said(i[k] as number, x.numbers)) {
      dropped.push(k);
      i[k] = null;
    }
  }
  // Une plage explicite remplace une cible et inversement.
  if (x.cote_totale_min !== null || x.cote_totale_max !== null) i.cote_totale_cible = x.cote_totale_cible;
  if (x.cote_totale_cible !== null) {
    i.cote_totale_min = null;
    i.cote_totale_max = null;
  }
  if (x.jour) i.jour = x.jour;
  else if (i.jour && !x.mentionsDay) {
    dropped.push("jour");
    i.jour = null;
  }
  i.issues = [...new Set([...x.issues, ...(x.mentionsMarket ? i.issues : [])])];
  i.marches = [...new Set([...x.marches, ...(x.mentionsMarket ? i.marches : [])])];
  if (!x.mentionsMarket && (ai.issues.length || ai.marches.length)) dropped.push("marches");
  if (x.risque) i.risque = x.risque;
  else if (i.risque) {
    dropped.push("risque");
    i.risque = null;
  }
  const nt = normalizeText(message);
  const inText = (name: string) => {
    const n = normalizeText(name).replace(/[^a-z0-9 ]/g, "");
    return n.length >= 3 && (nt.includes(n) || n.split(" ").some((w) => w.length >= 4 && nt.includes(w)));
  };
  for (const key of ["equipes", "exclure_equipes"] as const) {
    const kept = i[key].filter(inText);
    if (kept.length !== i[key].length) dropped.push(key);
    i[key] = kept;
  }
  if (i.intent === "creer_coupon" && (i.nombre_coupons ?? 1) > 1) i.intent = "variantes";
  return { intent: i, dropped };
}

/** Rappel de ce qui a été compris, pour que l'utilisateur le vérifie. */
export function describeRequest(i: Intent, label: string, lang: "fr" | "en" = "fr"): string {
  if (lang === "en") return describeRequestEn(i, label);
  const dec = (v: number) => v.toFixed(2).replace(/\.?0+$/, "").replace(".", ",");
  const parts: string[] = [];
  if (i.nombre_selections) parts.push(`${i.nombre_selections} sélection${i.nombre_selections > 1 ? "s" : ""}`);
  if (i.cote_totale_cible) parts.push(`cote totale proche de ${dec(i.cote_totale_cible)}`);
  if (i.cote_totale_min && i.cote_totale_max) parts.push(`cote totale entre ${dec(i.cote_totale_min)} et ${dec(i.cote_totale_max)}`);
  else if (i.cote_totale_min) parts.push(`cote totale d'au moins ${dec(i.cote_totale_min)}`);
  else if (i.cote_totale_max) parts.push(`cote totale de ${dec(i.cote_totale_max)} au plus`);
  if (i.cote_selection_min && i.cote_selection_max) parts.push(`cote par sélection entre ${dec(i.cote_selection_min)} et ${dec(i.cote_selection_max)}`);
  else if (i.cote_selection_min) parts.push(`cote par sélection d'au moins ${dec(i.cote_selection_min)}`);
  else if (i.cote_selection_max) parts.push(`cote par sélection de ${dec(i.cote_selection_max)} au plus`);
  if (i.competitions.length) parts.push(i.competitions.join(", "));
  if (i.equipes.length) parts.push(`avec ${i.equipes.join(", ")}`);
  if (i.exclure_equipes.length) parts.push(`sans ${i.exclure_equipes.join(", ")}`);
  if (i.issues.length || i.marches.length) parts.push(`marchés : ${[...i.marches, ...i.issues].join(", ")}`);
  if (i.risque) parts.push(`profil ${i.risque === "modere" ? "modéré" : i.risque}`);
  if (i.nombre_coupons && i.nombre_coupons > 1) parts.push(`${i.nombre_coupons} versions`);
  return `Demande comprise : ${[label, ...parts].join(" · ")}.`;
}

function describeRequestEn(i: Intent, label: string): string {
  const dec = (v: number) => v.toFixed(2).replace(/\.?0+$/, "");
  const parts: string[] = [];
  if (i.nombre_selections) parts.push(`${i.nombre_selections} selection${i.nombre_selections > 1 ? "s" : ""}`);
  if (i.cote_totale_cible) parts.push(`total odd close to ${dec(i.cote_totale_cible)}`);
  if (i.cote_totale_min && i.cote_totale_max) parts.push(`total odd between ${dec(i.cote_totale_min)} and ${dec(i.cote_totale_max)}`);
  else if (i.cote_totale_min) parts.push(`total odd of at least ${dec(i.cote_totale_min)}`);
  else if (i.cote_totale_max) parts.push(`total odd of ${dec(i.cote_totale_max)} at most`);
  if (i.cote_selection_min && i.cote_selection_max) parts.push(`odd per selection between ${dec(i.cote_selection_min)} and ${dec(i.cote_selection_max)}`);
  else if (i.cote_selection_min) parts.push(`odd per selection of at least ${dec(i.cote_selection_min)}`);
  else if (i.cote_selection_max) parts.push(`odd per selection of ${dec(i.cote_selection_max)} at most`);
  if (i.competitions.length) parts.push(i.competitions.join(", "));
  if (i.equipes.length) parts.push(`with ${i.equipes.join(", ")}`);
  if (i.exclure_equipes.length) parts.push(`without ${i.exclure_equipes.join(", ")}`);
  if (i.issues.length || i.marches.length) parts.push(`markets: ${[...i.marches, ...i.issues].join(", ")}`);
  if (i.risque) parts.push(`${i.risque === "modere" ? "balanced" : i.risque === "prudent" ? "cautious" : "bold"} profile`);
  if (i.nombre_coupons && i.nombre_coupons > 1) parts.push(`${i.nombre_coupons} versions`);
  return `Request understood: ${[label, ...parts].join(" · ")}.`;
}
