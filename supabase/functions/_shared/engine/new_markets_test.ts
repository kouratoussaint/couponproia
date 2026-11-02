// Nouveaux marchés (D2) : remboursé si nul et buts par équipe.
import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { impliedProbabilities, qualityGroup } from "./fiche.ts";
import { marketProbabilities, scoreMatrix } from "./poisson.ts";
import { normalizeBet } from "../sports/normalize.ts";
import { outcomeWins, selectionResult } from "../settlement/settle.ts";
import { compatible } from "../coupons/ai_consistency.ts";
import { outcomeLabel, qualityFamilyOf } from "../coupons/generator.ts";
import { parseIntent } from "../assistant/intent.ts";

Deno.test("cotes du fournisseur : remboursé si nul et buts par équipe", () => {
  assertEquals(normalizeBet("Home/Away", "Home"), { market: "DNB", outcome: "HOME", line: null });
  assertEquals(normalizeBet("Draw No Bet", "Away"), { market: "DNB", outcome: "AWAY", line: null });
  assertEquals(normalizeBet("Total - Home", "Over 1.5"), { market: "TTH", outcome: "OVER", line: 1.5 });
  assertEquals(normalizeBet("Total - Away", "Under 0.5"), { market: "TTA", outcome: "UNDER", line: 0.5 });
  assertEquals(normalizeBet("Total - Away", "Over 3.5"), null);
});

Deno.test("probabilités : DNB sans le nul, buts par équipe cohérents", () => {
  const p = marketProbabilities(scoreMatrix(1.6, 1.0));
  assertAlmostEquals(p["DNB.HOME"] + p["DNB.AWAY"], 1, 0.001);
  assertAlmostEquals(p["DNB.HOME"], p["1X2.HOME"] / (p["1X2.HOME"] + p["1X2.AWAY"]), 0.003);
  assertAlmostEquals(p["TTH.OVER.0.5"] + p["TTH.UNDER.0.5"], 1, 0.001);
  assert(p["TTH.OVER.0.5"] > p["TTH.OVER.1.5"] && p["TTH.OVER.1.5"] > p["TTH.OVER.2.5"]);
  // Domicile plus offensif (1,6 contre 1,0).
  assert(p["TTH.OVER.0.5"] > p["TTA.OVER.0.5"]);
  // P(domicile marque) = 1 - e^-λ (loi de Poisson, matrice tronquée à 10 buts).
  assertAlmostEquals(p["TTH.OVER.0.5"], 1 - Math.exp(-1.6), 0.002);
});

Deno.test("règlement : remboursé si nul annulé sur un nul ; buts par équipe", () => {
  assertEquals(outcomeWins("DNB.HOME", 2, 1), true);
  assertEquals(outcomeWins("DNB.HOME", 0, 1), false);
  assertEquals(outcomeWins("DNB.AWAY", 1, 1), null);
  const finished = (h: number, a: number) => ({
    status: "finished", statusShort: "FT", kickoffAt: "2026-11-01T15:00:00Z",
    homeGoals: h, awayGoals: a, ftHomeGoals: h, ftAwayGoals: a,
  });
  assertEquals(selectionResult("DNB.HOME", finished(1, 1), new Date()), "void");
  assertEquals(selectionResult("TTH.OVER.1.5", finished(2, 0), new Date()), "won");
  assertEquals(selectionResult("TTA.UNDER.0.5", finished(2, 1), new Date()), "lost");
  assertEquals(selectionResult("TTA.UNDER.1.5", finished(0, 1), new Date()), "won");
});

Deno.test("marge retirée par paire et familles d'évaluation", () => {
  const odds = [
    { market_code: "DNB", outcome_code: "HOME", line: null, odd_median: 1.5, odd_best: 1.55, bookmakers_count: 5 },
    { market_code: "DNB", outcome_code: "AWAY", line: null, odd_median: 2.5, odd_best: 2.6, bookmakers_count: 5 },
    { market_code: "TTH", outcome_code: "OVER", line: 1.5, odd_median: 2, odd_best: 2.1, bookmakers_count: 5 },
    { market_code: "TTH", outcome_code: "UNDER", line: 1.5, odd_median: 1.8, odd_best: 1.9, bookmakers_count: 5 },
  ];
  // deno-lint-ignore no-explicit-any
  const p = impliedProbabilities(odds as any);
  assertAlmostEquals(p.get("DNB.HOME")! + p.get("DNB.AWAY")!, 1, 0.001);
  assertAlmostEquals(p.get("TTH.OVER.1.5")! + p.get("TTH.UNDER.1.5")!, 1, 0.001);
  assertEquals(qualityGroup("TTA.OVER.0.5"), "TT");
  assertEquals(qualityGroup("DNB.HOME"), "DNB");
  assertEquals(qualityFamilyOf("TTH.UNDER.2.5"), "TT");
});

Deno.test("cohérence avec l'analyse IA : remboursé si nul dans la famille du résultat", () => {
  assert(compatible("DNB.HOME", "1X2.HOME"));
  assert(compatible("DNB.HOME", "DC.1X"));
  assert(!compatible("DNB.HOME", "1X2.AWAY"));
  assert(!compatible("DNB.AWAY", "DC.1X"));
});

Deno.test("libellés et compréhension de l'assistant", () => {
  assertEquals(outcomeLabel("DNB.AWAY", "Lille", "Lens"), "Lens (remboursé si nul)");
  assertEquals(outcomeLabel("TTH.OVER.1.5", "Lille", "Lens"), "Lille : plus de 1,5 buts");
  assertEquals(outcomeLabel("TTA.OVER.0.5", "Lille", "Lens"), "Lens : plus de 0,5 but");
  const r = parseIntent({
    intent: "creer_coupon",
    criteres: { marches: ["dnb", "TTH"], issues: ["TTA.OVER.0.5", "TTA.OVER.3.5", "DNB.DRAW"] },
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.marches, ["DNB", "TTH"]);
    assertEquals(r.value.issues, ["TTA.OVER.0.5"]);
  }
});
