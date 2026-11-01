import { assertEquals } from "jsr:@std/assert@1";
import { labDecision } from "./pricing.ts";

Deno.test("composition manuelle gratuite, même sans crédit", () => {
  assertEquals(labDecision("build", { total: 0 }, "FREE", 1), { ok: true, cost: 0 });
});

Deno.test("FREE : chaque calcul coûte le prix réglé", () => {
  for (const a of ["analyze", "optimize", "compare", "simulate"]) {
    assertEquals(labDecision(a, { total: 3 }, "FREE", 2), { ok: true, cost: 2 });
  }
});

Deno.test("FREE sans assez de crédits : refus avec le coût", () => {
  assertEquals(labDecision("simulate", { total: 1 }, "FREE", 2), { ok: false, error: "credits_required", cost: 2 });
});

Deno.test("forfait payant et équipe : gratuit", () => {
  assertEquals(labDecision("analyze", { total: 0 }, "STARTER", 1), { ok: true, cost: 0 });
  assertEquals(labDecision("analyze", { total: 0, unlimited: true }, "FREE", 1), { ok: true, cost: 0 });
});

Deno.test("prix 0 : gratuit pour tous", () => {
  assertEquals(labDecision("compare", { total: 0 }, "FREE", 0), { ok: true, cost: 0 });
});
