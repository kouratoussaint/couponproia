// Tests unitaires du Laboratoire : `deno test supabase/functions/_shared`
import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import type { CouponLine } from "../assistant/actions.ts";
import type { Candidate } from "../coupons/generator.ts";
import { alternativesFor, compareCoupons, correctCountDistribution, simulate } from "./lab.ts";

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
  ...p,
});

Deno.test("loi du nombre de sélections justes : somme 1, cas connus", () => {
  const d = correctCountDistribution([0.5, 0.5]);
  assertEquals(d, [0.25, 0.5, 0.25]);
  const d3 = correctCountDistribution([0.6, 0.7, 0.8]);
  assertAlmostEquals(d3.reduce((s, x) => s + x, 0), 1, 1e-3);
  assertAlmostEquals(d3[3], 0.336, 1e-4);
});

Deno.test("simulation : reproductible, cohérente avec la probabilité, étiquetée", () => {
  const s = simulate([0.6, 0.7, 0.8], 4.5, 1000, 7);
  assertEquals(s.probability_all_correct, 0.336);
  assert(s.simulated_wins >= s.wins_interval[0] - 20 && s.simulated_wins <= s.wins_interval[1] + 20);
  assertEquals(simulate([0.6, 0.7, 0.8], 4.5, 1000, 7).simulated_wins, s.simulated_wins, "même graine, même tirage");
  assert(s.label.includes("pas un résultat réel"));
  assertEquals(s.model_return_per_unit, 1.512);
});

Deno.test("comparaison : diversification, corrélations, marchés non validés", () => {
  const [a, b] = compareCoupons([
    { id: "a", title: "A", lines: [line({ position: 1 }), line({ position: 2 }), line({ position: 3, competition: "Ligue 1" })] },
    { id: "b", title: "B", lines: [line({ position: 1, key: "OU.OVER.2.5", reliability: "faible" }), line({ position: 2, competition: "Serie A", kickoffAt: "2026-11-02T15:00:00Z" })] },
  ], { "1X2": true, OU: false });
  assertEquals(a.correlated_pairs, 1);
  assertEquals(a.competitions, 2);
  assertEquals(a.total_odd, 5.83);
  assertEquals(b.correlated_pairs, 0);
  assertEquals(b.unvalidated_markets, 1);
  assertEquals(b.low_reliability, 1);
  assertEquals(b.diversification, 1);
});

Deno.test("optimisation : alternatives plus probables, nouvelle cote recalculée", () => {
  const lines = [line({ position: 1, modelProbability: 0.72, odd: 1.5 }), line({ position: 2, modelProbability: 0.45, odd: 2.2 })];
  const cand = (p: Partial<Candidate> & { matchId: number; key: string }): Candidate => ({
    competitionId: 1, competitionName: "PL", kickoffAt: "2026-11-01T15:00:00Z", home: `H${p.matchId}`, away: `A${p.matchId}`,
    marketCode: p.key.split(".")[0], outcomeCode: p.key.split(".")[1], line: null, odd: 2, oddBest: 2.1, bookmakers: 5,
    oddsCapturedAt: "2026-10-31T06:00:00Z", modelProbability: 0.5, impliedProbability: 0.48, edge: 0.02, reliability: "bonne",
    justification: "", ...p,
  });
  const alts = alternativesFor(lines, [
    cand({ matchId: 2, key: "DC.X2", odd: 1.4, modelProbability: 0.7 }),
    cand({ matchId: 9, key: "1X2.HOME", odd: 2.1, modelProbability: 0.52 }),
    cand({ matchId: 10, key: "1X2.HOME", odd: 3.5, modelProbability: 0.6 }),
    cand({ matchId: 11, key: "1X2.HOME", odd: 2.0, modelProbability: 0.55, reliability: "faible" }),
  ], 1);
  assertEquals(alts.map((a) => [a.match_id, a.kind]), [[2, "meme_match"], [9, "autre_match"]]);
  assertEquals(alts[0].replace_position, 2);
  assertEquals(alts[0].new_total_odd, 2.1);
  assertEquals(alts[1].new_total_odd, 3.15);
});
