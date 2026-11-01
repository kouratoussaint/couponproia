import { assert, assertEquals } from "jsr:@std/assert@1";
import { analysisAllowed, analysisDecision } from "./access.ts";

Deno.test("analyse : forfait payant ou crédits, sinon refus", () => {
  assert(analysisAllowed({ plan: "STARTER", total: 0 }));
  assert(analysisAllowed({ plan: "FREE", total: 2 }));
  assert(analysisAllowed({ plan: "FREE", total: 0, unlimited: true }));
  assert(!analysisAllowed({ plan: "FREE", total: 0 }));
  assert(!analysisAllowed(null));
});

Deno.test("accès du 01/11 : quota pour un forfait payant, crédits pour FREE", () => {
  assertEquals(analysisDecision({ total: 0 }, "STARTER", 3, 10, 1), { ok: true, source: "plan", cost: 0 });
  assertEquals(analysisDecision({ total: 0 }, "STARTER", 10, 10, 1), { ok: false, error: "daily_limit", limit: 10 });
  assertEquals(analysisDecision({ total: 0 }, "FREE", 0, 2, 1), { ok: false, error: "credits_required", cost: 1 });
  assertEquals(analysisDecision({ total: 3 }, "FREE", 50, 2, 1), { ok: true, source: "credit", cost: 1 });
  assertEquals(analysisDecision({ total: 0, unlimited: true }, "FREE", 0, 2, 1), { ok: true, source: "plan", cost: 0 });
  assertEquals(analysisDecision({ total: 0 }, "FREE", 0, 2, 0), { ok: true, source: "credit", cost: 0 });
});
