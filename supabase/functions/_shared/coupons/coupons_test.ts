// Tests unitaires du générateur de coupons : `deno test supabase/functions/_shared`
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildCoupons,
  type Candidate,
  DEFAULT_CRITERIA,
  defaultSummary,
  filterCandidates,
  fingerprintOf,
  justificationFor,
  type LiveCheck,
  parseCriteria,
  qualityCheck,
  riskLevel,
} from "./generator.ts";

const NOW = new Date("2026-11-02T07:00:00Z");
const inHours = (h: number) => new Date(NOW.getTime() + h * 3600_000).toISOString();

let nextId = 1;
function cand(p: Partial<Candidate> & { matchId: number }): Candidate {
  return {
    competitionId: 1,
    competitionName: "Premier League",
    kickoffAt: inHours(10),
    home: `Dom${p.matchId}`,
    away: `Ext${p.matchId}`,
    key: "1X2.HOME",
    marketCode: "1X2",
    outcomeCode: "HOME",
    line: null,
    odd: 1.8,
    oddBest: 1.9,
    bookmakers: 8,
    oddsCapturedAt: inHours(-2),
    modelProbability: 0.6,
    impliedProbability: 0.54,
    edge: 0.06,
    reliability: "bonne",
    justification: `j${nextId++}`,
    ...p,
  };
}

const VALID = { "1X2": true, OU: false, BTTS: false };

Deno.test("critères : valeurs par défaut, bornes et cohérence", () => {
  const c = parseCriteria({ min_selections: 5, max_selections: 2, min_total_odd: "abc", min_reliability: "géniale" });
  assertEquals(c.min_selections, 5);
  assertEquals(c.max_selections, 5, "max relevé au min");
  assertEquals(c.min_total_odd, DEFAULT_CRITERIA.min_total_odd);
  assertEquals(c.min_reliability, "moyenne");
  assertEquals(c.require_validated_markets, true);
});

Deno.test("filtres : chaque motif d'exclusion est compté", () => {
  const all = [
    cand({ matchId: 1 }),
    cand({ matchId: 2, kickoffAt: inHours(0.2) }),
    cand({ matchId: 3, kickoffAt: inHours(40) }),
    cand({ matchId: 4, key: "OU.OVER.2.5", marketCode: "OU", outcomeCode: "OVER", line: 2.5 }),
    cand({ matchId: 5, odd: 4.5 }),
    cand({ matchId: 6, modelProbability: 0.3 }),
    cand({ matchId: 7, edge: -0.1 }),
    cand({ matchId: 8, reliability: "faible" }),
    cand({ matchId: 9, oddsCapturedAt: inHours(-20) }),
    cand({ matchId: 10, key: "DC.1X", marketCode: "DC", outcomeCode: "1X", odd: 1.3, modelProbability: 0.8 }),
  ];
  const { kept, excluded } = filterCandidates(all, parseCriteria({ markets: ["1X2", "DC", "OU"], max_selection_odd: 3 }), NOW, VALID);
  assertEquals(kept.map((c) => c.matchId), [1, 10]);
  assertEquals(excluded["marché non validé par l'évaluation du moteur"], 1);
  assertEquals(excluded["coup d'envoi trop proche"], 1);
  assertEquals(excluded["hors fenêtre de matchs"], 1);
  assertEquals(excluded["fiabilité insuffisante"], 1);
  assertEquals(excluded["cote trop ancienne"], 1);
  // Sans évaluation enregistrée, aucun marché n'est « validé ».
  assertEquals(filterCandidates(all, DEFAULT_CRITERIA, NOW, null).kept.length, 0);
});

Deno.test("combinaison : la plus probable dans la fourchette de cote, un match une fois", () => {
  const pool = [
    cand({ matchId: 1, odd: 1.5, modelProbability: 0.7 }),
    cand({ matchId: 1, key: "DC.1X", odd: 1.2, modelProbability: 0.85 }),
    cand({ matchId: 2, odd: 1.6, modelProbability: 0.66 }),
    cand({ matchId: 3, odd: 2.2, modelProbability: 0.5 }),
    cand({ matchId: 4, odd: 1.9, modelProbability: 0.55 }),
  ];
  const criteria = parseCriteria({ min_selections: 2, max_selections: 3, min_total_odd: 2.5, max_total_odd: 4 });
  const [best] = buildCoupons(pool, criteria);
  assert(best, "un coupon trouvé");
  assert(best.totalOdd >= 2.5 && best.totalOdd <= 4, `cote ${best.totalOdd}`);
  assertEquals(new Set(best.selections.map((s) => s.matchId)).size, best.selections.length);
  // Meilleur choix : 1X2.HOME m1 (1,5) × m2 (1,6) = 2,40 < 2,5 ; m1 1,5 × m4 1,9 = 2,85 (p 0,385)
  // contre m2 1,6 × m4 1,9 = 3,04 (p 0,363) ou DC m1 1,2 × m3 2,2 = 2,64 (p 0,425) → le plus probable.
  assertEquals(best.fingerprint, fingerprintOf([{ matchId: 1, key: "DC.1X" }, { matchId: 3, key: "1X2.HOME" }]));
  assertEquals(best.totalOdd, 2.64);
  assertEquals(best.combinedProbability, 0.425);
});

Deno.test("combinaison : plusieurs coupons distincts, doublons exclus, échec si impossible", () => {
  const pool = Array.from({ length: 8 }, (_, i) => cand({ matchId: i + 1, odd: 1.5 + i * 0.05, modelProbability: 0.7 - i * 0.02 }));
  const criteria = parseCriteria({ min_selections: 2, max_selections: 3, min_total_odd: 2.5, max_total_odd: 4, coupons_per_run: 3 });
  const coupons = buildCoupons(pool, criteria);
  assertEquals(coupons.length, 3);
  assertEquals(new Set(coupons.map((c) => c.fingerprint)).size, 3);
  const again = buildCoupons(pool, { ...criteria, coupons_per_run: 1 }, new Set([coupons[0].fingerprint]));
  assert(again[0].fingerprint !== coupons[0].fingerprint, "empreinte déjà prise évitée");
  assertEquals(buildCoupons(pool, parseCriteria({ min_total_odd: 50, max_total_odd: 60, max_selections: 3 })).length, 0);
});

Deno.test("plafond par compétition respecté", () => {
  const pool = [1, 2, 3, 4].map((i) => cand({ matchId: i, odd: 1.6, competitionId: i <= 3 ? 1 : 2 }));
  const [c] = buildCoupons(pool, parseCriteria({ min_selections: 3, max_selections: 3, min_total_odd: 3, max_total_odd: 5, max_per_competition: 2 }));
  assertEquals(c.selections.filter((s) => s.competitionId === 1).length, 2);
});

Deno.test("risque estimé selon la probabilité combinée", () => {
  const t = { prudent: 0.4, equilibre: 0.18 };
  assertEquals(riskLevel(0.45, t), "prudent");
  assertEquals(riskLevel(0.25, t), "equilibre");
  assertEquals(riskLevel(0.05, t), "audacieux");
});

Deno.test("contrôle qualité : motifs de refus explicites", () => {
  const criteria = parseCriteria({ min_selections: 2, max_selections: 3, min_total_odd: 2.5, max_total_odd: 4 });
  const [coupon] = buildCoupons([cand({ matchId: 1, odd: 1.7 }), cand({ matchId: 2, odd: 1.8 })], criteria);
  const ok: LiveCheck = { matchExists: true, status: "scheduled", kickoffAt: inHours(10), currentOdd: 1.7, oddsCapturedAt: inHours(-1) };
  const live = new Map([["1:1X2.HOME", ok], ["2:1X2.HOME", ok]]);
  assertEquals(qualityCheck(coupon, live, criteria, NOW, new Set()), []);

  const bad = new Map([
    ["1:1X2.HOME", { ...ok, status: "postponed" }],
    ["2:1X2.HOME", { ...ok, currentOdd: null }],
  ]);
  const reasons = qualityCheck(coupon, bad, criteria, NOW, new Set([coupon.fingerprint]));
  assert(reasons.some((r) => r.includes("postponed")));
  assert(reasons.some((r) => r.includes("plus cotée")));
  assert(reasons.some((r) => r.includes("déjà en circulation")));
  const late = qualityCheck(coupon, live, criteria, new Date(Date.parse(inHours(9.9))), new Set());
  assert(late.some((r) => r.includes("coup d'envoi")));
});

Deno.test("textes calculés : justification factuelle et analyse de repli", () => {
  const c = cand({ matchId: 1, modelProbability: 0.584, impliedProbability: 0.521, edge: 0.063 });
  const j = justificationFor(c, {
    model: { expected_goals_home: 1.72, expected_goals_away: 0.9 },
    teams: { home: { form: "VVNDV", standing: { rank: 3 } }, away: { form: "DNDVN", standing: { rank: 14 } } },
  });
  assert(j.includes("58 % contre 52 %"), j);
  assert(j.includes("+6 pts") && j.includes("1,72") && j.includes("3e contre 14e"), j);
  const [coupon] = buildCoupons([cand({ matchId: 1, odd: 1.7 }), cand({ matchId: 2, odd: 1.8, modelProbability: 0.52 })],
    parseCriteria({ min_total_odd: 2.5, max_total_odd: 4 }));
  const s = defaultSummary(coupon);
  assert(s.analyse_generale.includes("cote totale de 3,06"), s.analyse_generale);
  assert(s.analyse_generale.includes("la plus fragile"));
});

import { dueSlots, localDate, tzOffsetMs } from "./schedule.ts";

Deno.test("créneaux : heure locale, rattrapage limité, passage de minuit", () => {
  const at = new Date("2026-11-02T07:20:00Z");
  assertEquals(tzOffsetMs(at, "Africa/Ouagadougou"), 0);
  assertEquals(dueSlots(["07:00", "12:00"], at, "Africa/Ouagadougou").map((s) => s.slotKey), ["2026-11-02 07:00"]);
  assertEquals(dueSlots(["07:00"], new Date("2026-11-02T08:30:00Z"), "Africa/Ouagadougou"), []);
  assertEquals(dueSlots(["07:00"], new Date("2026-11-02T06:59:00Z"), "Africa/Ouagadougou"), []);
  // Paris (UTC+1 en novembre) : 07:00 locale = 06:00 UTC
  const paris = dueSlots(["07:00"], new Date("2026-11-02T06:10:00Z"), "Europe/Paris");
  assertEquals(paris[0].slotAt.toISOString(), "2026-11-02T06:00:00.000Z");
  // 23:50 de la veille encore dans la fenêtre de rattrapage à 00:20
  assertEquals(dueSlots(["23:50"], new Date("2026-11-03T00:20:00Z"), "UTC")[0].slotKey, "2026-11-02 23:50");
  assertEquals(localDate(new Date("2026-11-02T23:30:00Z"), "Europe/Paris"), "2026-11-03");
});

Deno.test("filtres : compétition où le moteur ne bat pas la référence exclue", () => {
  const all = [cand({ matchId: 1 }), cand({ matchId: 2, competitionName: "UEFA Champions League", competitionId: 2 })];
  const { kept, excluded } = filterCandidates(all, DEFAULT_CRITERIA, NOW, VALID, { "UEFA Champions League": false, "Premier League": true });
  assertEquals(kept.map((c) => c.matchId), [1]);
  assertEquals(excluded["compétition où le moteur ne bat pas la référence"], 1);
});

Deno.test("filtres : un désaccord trop fort avec le marché est écarté", () => {
  const all = [cand({ matchId: 1, edge: 0.06 }), cand({ matchId: 2, edge: 0.27, modelProbability: 0.6, impliedProbability: 0.33 })];
  const { kept, excluded } = filterCandidates(all, DEFAULT_CRITERIA, NOW, VALID);
  assertEquals(kept.map((c) => c.matchId), [1]);
  assertEquals(excluded["désaccord trop fort avec le marché"], 1);
});

import { byCompetition } from "../engine/quality.ts";

Deno.test("qualité par compétition : saisons regroupées, petits échantillons ignorés", () => {
  const q = byCompetition({
    "Ligue 1 2025": { matches: 278, brierModel: 0.63, brierBaseline: 0.66 },
    "Ligue 1 2026": { matches: 50, brierModel: 0.70, brierBaseline: 0.62 },
    "Coupe X 2026": { matches: 40, brierModel: 0.7, brierBaseline: 0.6 },
  });
  assertEquals(q, { "Ligue 1": true });
});

Deno.test("sélections imposées : conservées, complétées dans la fourchette", () => {
  const fixed = cand({ matchId: 99, odd: 2.0, modelProbability: 0.5 });
  const pool = [1, 2, 3, 4].map((i) => cand({ matchId: i, odd: 1.4 + i * 0.1, modelProbability: 0.75 - i * 0.03 }));
  const [c] = buildCoupons(pool, parseCriteria({ min_selections: 3, max_selections: 3, min_total_odd: 4, max_total_odd: 6 }), new Set(), 200_000, [fixed]);
  assert(c.selections.some((s) => s.matchId === 99), "la sélection imposée reste");
  assertEquals(c.selections.length, 3);
  assert(c.totalOdd >= 4 && c.totalOdd <= 6);
  const keys = parseCriteria({ markets: ["OU"], allowed_keys: ["OU.OVER.1.5"] });
  const { kept } = filterCandidates(
    [cand({ matchId: 7, key: "OU.OVER.1.5", marketCode: "OU", outcomeCode: "OVER", line: 1.5 }),
     cand({ matchId: 8, key: "OU.OVER.2.5", marketCode: "OU", outcomeCode: "OVER", line: 2.5 })],
    { ...keys, require_validated_markets: false }, NOW, VALID);
  assertEquals(kept.map((k) => k.key), ["OU.OVER.1.5"]);
});

Deno.test("recherche : une cote cible atteignable n'est pas manquée à cause des cotes basses", () => {
  // 50 matchs : double chance à 1,20 (80 %) et victoire à 1,65 (55 %). Cible : 3 sélections, cote ≈ 4.
  const pool: Candidate[] = [];
  for (let i = 1; i <= 50; i++) {
    pool.push(cand({ matchId: i, key: "DC.1X", odd: 1.2, modelProbability: 0.8 - i * 0.001 }));
    pool.push(cand({ matchId: i, key: "1X2.HOME", odd: 1.62 + (i % 5) * 0.01, modelProbability: 0.55 - i * 0.001 }));
  }
  const [c] = buildCoupons(pool, parseCriteria({ min_selections: 3, max_selections: 3, min_total_odd: 3.4, max_total_odd: 4.6 }));
  assert(c, "coupon trouvé");
  assert(c.totalOdd >= 3.4 && c.totalOdd <= 4.6, `cote ${c.totalOdd}`);
});

Deno.test("coupon du jour : un seul par jour de match, limite réglable pour les autres catégories", async () => {
  const { dailyLimit, parseCriteria } = await import("./generator.ts");
  const { localDayBounds } = await import("./schedule.ts");
  assertEquals(dailyLimit("du_jour", parseCriteria({})), 1);
  assertEquals(dailyLimit("prudent", parseCriteria({})), 0);
  assertEquals(dailyLimit("prudent", parseCriteria({ max_per_day: 2 })), 2);
  assertEquals(dailyLimit("du_jour", parseCriteria({ max_per_day: 0 })), 0);
  assertEquals(parseCriteria({ max_per_day: 99 }).max_per_day, 20);
  const ouaga = localDayBounds("2026-10-31", "Africa/Ouagadougou");
  assertEquals(ouaga.start.toISOString(), "2026-10-31T00:00:00.000Z");
  assertEquals(ouaga.end.toISOString(), "2026-11-01T00:00:00.000Z");
  const paris = localDayBounds("2026-07-14", "Europe/Paris");
  assertEquals(paris.start.toISOString(), "2026-07-13T22:00:00.000Z");
});
