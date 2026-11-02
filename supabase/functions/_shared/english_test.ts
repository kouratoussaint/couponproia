// Tests : textes du serveur et de l'IA en anglais (D5 partie 2).
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { extractConstraints, describeRequest, reconcileIntent } from "./assistant/keywords.ts";
import { dateRange, type Intent } from "./assistant/intent.ts";
import { diagnoseCoupon, exclusionLabel } from "./assistant/actions.ts";
import { type Candidate, defaultSummary, justificationFor, outcomeLabelEn, propose } from "./coupons/generator.ts";
import { FORBIDDEN, isGrounded } from "./ai/validate.ts";
import { ENGLISH_INSTRUCTION, withLanguage } from "./ai/language.ts";
import { simulate } from "./lab/lab.ts";

const NOW = new Date("2026-11-01T08:00:00Z"); // dimanche
const TZ = "Africa/Ouagadougou";

const base: Intent = {
  intent: "creer_coupon", jour: null, competitions: [], equipes: [], exclure_equipes: [],
  nombre_selections: null, cote_totale_cible: null, cote_totale_min: null, cote_totale_max: null,
  cote_selection_min: null, cote_selection_max: null, marches: [], issues: [], risque: null,
  nombre_coupons: null, retirer_positions: [], remplacer_plus_fragiles: 0, ajouter: 0, reponse: "",
};

Deno.test("assistant : demande en anglais comprise (chiffres, jour, marchés, risque)", () => {
  const a = extractConstraints("Make me a coupon of three matches for tomorrow with total odds around 5", NOW, TZ);
  assertEquals(a.nombre_selections, 3);
  assertEquals(a.jour, "demain");
  assertEquals(a.cote_totale_cible, 5);
  const b = extractConstraints("2 coupons, odds between 4 and 6, over 2 goals, safe picks", NOW, TZ);
  assertEquals(b.nombre_coupons, 2);
  assertEquals([b.cote_totale_min, b.cote_totale_max], [4, 6]);
  assert(b.issues.includes("OU.OVER.2.5"));
  assertEquals(b.risque, "prudent");
  const c = extractConstraints("odds per match at least 1.5 on saturday", NOW, TZ);
  assertEquals(c.cote_selection_min, 1.5);
  assertEquals(c.cote_totale_min, null);
  assertEquals(c.jour, "2026-11-07");
  // Les chiffres écrits en anglais ne sont plus retirés de la compréhension de l'IA.
  const { intent } = reconcileIntent({ ...base, nombre_selections: 4 }, "four games this weekend please", NOW, TZ);
  assertEquals(intent.nombre_selections, 4);
  assertEquals(intent.jour, "week_end");
});

Deno.test("assistant : textes et période en anglais", () => {
  assertEquals(dateRange("demain", NOW, TZ, "en").label, "tomorrow");
  assertEquals(dateRange(null, NOW, TZ, "en").label, "in the next 48 hours");
  const d = describeRequest({ ...base, nombre_selections: 3, cote_totale_min: 4, cote_totale_max: 6, risque: "modere" }, "tomorrow", "en");
  assertEquals(d, "Request understood: tomorrow · 3 selections · total odd between 4 and 6 · balanced profile.");
  assertEquals(exclusionLabel("cote hors fourchette", "en"), "odd out of range");
  assertEquals(exclusionLabel("cote hors fourchette", "fr"), "cote hors fourchette");
});

const cand = (p: Partial<Candidate>): Candidate => ({
  matchId: 1, competitionId: 1, competitionName: "Ligue 1", kickoffAt: "2026-11-02T19:00:00Z",
  home: "Lille", away: "Lens", key: "1X2.HOME", marketCode: "1X2", outcomeCode: "HOME", line: null,
  odd: 1.9, oddBest: 1.95, bookmakers: 8, oddsCapturedAt: "2026-11-01T07:00:00Z",
  modelProbability: 0.55, impliedProbability: 0.5, edge: 0.05, reliability: "bonne", justification: "",
  ...p,
} as Candidate);

Deno.test("coupons : libellés, justification et résumé en anglais", () => {
  assertEquals(outcomeLabelEn("OU.UNDER.3.5", "Lille", "Lens"), "Under 3.5 goals");
  assertEquals(outcomeLabelEn("TTA.OVER.0.5", "Lille", "Lens"), "Lens: over 0.5 goal");
  const fiche = {
    model: { expected_goals_home: 1.6, expected_goals_away: 1.1 },
    teams: { home: { form: "VVNDV", standing: { rank: 1 } }, away: { form: "DNV", standing: { rank: 2 } } },
  };
  const j = justificationFor(cand({}), fiche, "en");
  assertEquals(
    j,
    "Model: 55% vs 50% for the market (edge +5 pts); expected goals 1.60 – 1.10; form (W/D/L, most recent first): Lille WWDLW, Lens LDW; table: 1st vs 2nd.",
  );
  const p = propose([cand({}), cand({ matchId: 2, home: "Lyon", away: "Nice", key: "1X2.DRAW", modelProbability: 0.3 })]);
  const s = defaultSummary(p, "en");
  assertStringIncludes(s.analyse_generale, "2 selections for a total odd of");
  assertStringIncludes(s.analyse_generale, "Strongest selection: Lille win");
  assert(!FORBIDDEN.test([s.analyse_generale, ...s.points_de_vigilance].join(" ")));
});

Deno.test("analyse d'un coupon en anglais", () => {
  const d = diagnoseCoupon([
    {
      position: 1, matchId: 1, home: "Lille", away: "Lens", competition: "Ligue 1", kickoffAt: "2026-11-02T19:00:00Z",
      key: "1X2.HOME", odd: 1.9, modelProbability: 0.55, impliedProbability: 0.5, edge: -0.02, reliability: "faible",
      currentOdd: 2.1,
    },
  ], null, NOW, "en");
  assertStringIncludes(d.fragiles[0].raison, "model probability 55%, low reliability");
  assertStringIncludes(d.alertes[0], "the odd moved from 1.90 to 2.10");
  assertStringIncludes(d.qualite.at(-1)!, "Line-ups, injuries and suspensions");
});

Deno.test("IA : consigne anglaise, mots interdits et ancrage en anglais", () => {
  assertEquals(withLanguage("PROMPT", "fr"), "PROMPT");
  assertStringIncludes(withLanguage("PROMPT", "en"), ENGLISH_INSTRUCTION);
  for (const w of ["a guaranteed win", "sure bet", "risk-free", "big winnings", "100% safe"]) assert(FORBIDDEN.test(w), w);
  assert(!FORBIDDEN.test("Make sure the line-ups are confirmed"));
  assert(isGrounded("Lille have the better home record and the higher expected goals in this match."));
  assertStringIncludes(simulate([0.5, 0.6], 3.2, 500, 42, "en").label, "This is not a real result nor a forecast of profit.");
});
