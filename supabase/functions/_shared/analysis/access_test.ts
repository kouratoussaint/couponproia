import { assert } from "jsr:@std/assert@1";
import { analysisAllowed } from "./access.ts";

Deno.test("analyse : forfait payant ou crédits, sinon refus", () => {
  assert(analysisAllowed({ plan: "STARTER", total: 0 }));
  assert(analysisAllowed({ plan: "FREE", total: 2 }));
  assert(analysisAllowed({ plan: "FREE", total: 0, unlimited: true }));
  assert(!analysisAllowed({ plan: "FREE", total: 0 }));
  assert(!analysisAllowed(null));
});
