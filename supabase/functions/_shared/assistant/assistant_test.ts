// Tests unitaires de l'assistant : `deno test supabase/functions/_shared`
import { assert, assertEquals } from "jsr:@std/assert@1";
import { type CouponLine, diagnoseCoupon, opportunities } from "./actions.ts";
import { criteriaFromIntent, dateRange, type Intent, matchNames, parseIntent } from "./intent.ts";

const base = (p: Partial<Intent> = {}): Intent => ({
  ...(parseIntent({ intent: "creer_coupon", criteres: {}, reponse: "" }) as { ok: true; value: Intent }).value,
  ...p,
});

Deno.test("intention : valeurs bornées, inconnues ignorées", () => {
  const r = parseIntent({
    intent: "creer_coupon",
    criteres: { nombre_selections: "5", cote_totale_cible: "10,5", marches: ["ou", "corners"], issues: ["OU.OVER.1.5", "X"], risque: "modere", jour: "demain" },
    modification: { remplacer_plus_fragiles: 9 },
    reponse: "D'accord",
  });
  assert(r.ok);
  assertEquals(r.value.nombre_selections, 5);
  assertEquals(r.value.cote_totale_cible, 10.5);
  assertEquals(r.value.marches, ["OU"]);
  assertEquals(r.value.issues, ["OU.OVER.1.5"]);
  assertEquals(r.value.remplacer_plus_fragiles, 6);
  assertEquals(r.value.jour, "demain");
  assert(!parseIntent({ intent: "pirater" }).ok);
  assert(!parseIntent({ intent: "question", reponse: "" }).ok, "une question exige une réponse");
});

Deno.test("critères : cote cible ±15 %, nombre de matchs, risque, marchés demandés", () => {
  const { criteria, warnings } = criteriaFromIntent(base({ nombre_selections: 5, cote_totale_cible: 10, risque: "modere" }), 24);
  assertEquals([criteria.min_selections, criteria.max_selections], [5, 5]);
  assertEquals(criteria.min_total_odd, 8.5);
  assertEquals(Math.round(criteria.max_total_odd * 100) / 100, 11.5);
  assertEquals(criteria.min_model_probability, 0.45);
  assertEquals(criteria.require_validated_markets, true);
  assertEquals(warnings, []);
  const ou = criteriaFromIntent(base({ issues: ["OU.OVER.1.5"] }), 24);
  assertEquals(ou.criteria.markets, ["OU"]);
  assertEquals(ou.criteria.allowed_keys, ["OU.OVER.1.5"]);
  assertEquals(ou.criteria.require_validated_markets, false, "l'utilisateur garde le contrôle");
  assertEquals(ou.warnings.length, 1, "mais il est prévenu");
  assertEquals(criteriaFromIntent(base({ intent: "variantes" }), 24).criteria.coupons_per_run, 3);
});

Deno.test("périodes : aujourd'hui, demain, week-end, date (heure locale)", () => {
  const now = new Date("2026-10-30T17:00:00Z"); // vendredi
  const today = dateRange("aujourdhui", now, "Africa/Ouagadougou");
  assertEquals(today.until.toISOString(), "2026-10-31T00:00:00.000Z");
  const tomorrow = dateRange("demain", now, "Africa/Ouagadougou");
  assertEquals([tomorrow.from.toISOString(), tomorrow.until.toISOString()], ["2026-10-31T00:00:00.000Z", "2026-11-01T00:00:00.000Z"]);
  const we = dateRange("week_end", now, "Africa/Ouagadougou");
  assertEquals([we.from.toISOString(), we.until.toISOString()], ["2026-10-31T00:00:00.000Z", "2026-11-02T00:00:00.000Z"]);
  assertEquals(dateRange("2026-11-07", now, "Africa/Ouagadougou").label, "le 07/11");
  assertEquals(dateRange(null, now, "UTC").until.toISOString(), "2026-11-01T17:00:00.000Z");
});

Deno.test("noms : casse et accents ignorés, inconnus signalés", () => {
  const known = [{ id: 1, name: "Premier League" }, { id: 2, name: "Ligue 1" }, { id: 3, name: "Atlético Madrid" }];
  assertEquals(matchNames(["premier league", "atletico"], known), { ids: [1, 3], unknown: [] });
  assertEquals(matchNames(["Serie Z"], known).unknown, ["Serie Z"]);
});

const line = (p: Partial<CouponLine> & { position: number }): CouponLine => ({
  matchId: p.position,
  home: `Dom${p.position}`,
  away: `Ext${p.position}`,
  competition: "Premier League",
  kickoffAt: "2026-11-01T15:00:00Z",
  key: "1X2.HOME",
  odd: 1.8,
  modelProbability: 0.6,
  impliedProbability: 0.55,
  edge: 0.05,
  reliability: "bonne",
  status: "scheduled",
  currentOdd: 1.8,
  ...p,
});

Deno.test("diagnostic : sélections fragiles, alertes, corrélations, qualité", () => {
  const d = diagnoseCoupon([
    line({ position: 1, modelProbability: 0.72 }),
    line({ position: 2, modelProbability: 0.41, reliability: "faible", edge: -0.04 }),
    line({ position: 3, currentOdd: 2.1 }),
    line({ position: 4, key: "OU.OVER.2.5", status: "postponed" }),
  ], { "1X2": true, OU: false }, new Date("2026-10-31T10:00:00Z"));
  assertEquals(d.fragiles[0].position, 2);
  assert(d.fragiles[0].raison.includes("fiabilité faible"));
  assert(d.alertes.some((a) => a.includes("postponed")));
  assert(d.alertes.some((a) => a.includes("1,80 à 2,10")));
  assert(d.qualite.some((q) => q.includes("4 sélections en Premier League")));
  assert(d.qualite.some((q) => q.includes("Marchés OU")));
  assertEquals(d.total_odd, 10.5);
});

Deno.test("opportunités : une par match, triées par écart", () => {
  const c = (matchId: number, key: string, p: number, edge: number) => ({
    matchId, competitionId: 1, competitionName: "L", kickoffAt: "2026-11-01T15:00:00Z", home: "A", away: "B", key,
    marketCode: key.split(".")[0], outcomeCode: key.split(".")[1], line: null, odd: 1.8, oddBest: 1.9, bookmakers: 5,
    oddsCapturedAt: "2026-10-31T06:00:00Z", modelProbability: p, impliedProbability: p - edge, edge,
    reliability: "bonne" as const, justification: "",
  });
  const o = opportunities([c(1, "1X2.HOME", 0.6, 0.02), c(1, "DC.1X", 0.8, 0.05), c(2, "1X2.AWAY", 0.5, 0.08)]);
  assertEquals(o.map((x) => [x.match_id, x.key]), [[2, "1X2.AWAY"], [1, "DC.1X"]]);
});
