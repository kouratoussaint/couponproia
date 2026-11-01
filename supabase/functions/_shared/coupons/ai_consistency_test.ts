import { assert, assertEquals } from "jsr:@std/assert@1";
import { aiJustification, aiPositionOf, compatible, contradictions } from "./ai_consistency.ts";

const genoa = aiPositionOf({
  recommandation_possible: true,
  resume: "Match serré.",
  marches_envisageables: [{ cle: "1X2.AWAY", justification: "Genoa attaque mieux." }],
});

Deno.test("Lecce – Genoa : « Lecce ou nul » contredit « Victoire Genoa »", () => {
  assertEquals(contradictions("DC.1X", genoa), ["1X2.AWAY"]);
  assertEquals(contradictions("1X2.HOME", genoa), ["1X2.AWAY"]);
  assertEquals(contradictions("1X2.DRAW", genoa), ["1X2.AWAY"]);
  assertEquals(contradictions("DC.X2", genoa), []);
  assertEquals(contradictions("DC.12", genoa), []);
  assertEquals(contradictions("1X2.AWAY", genoa), []);
  assertEquals(contradictions("OU.OVER.2.5", genoa), [], "marché non tranché");
});

Deno.test("buts et « les deux marquent »", () => {
  assert(compatible("OU.OVER.1.5", "OU.OVER.2.5"));
  assert(!compatible("OU.OVER.3.5", "OU.OVER.2.5"));
  assert(!compatible("OU.UNDER.3.5", "OU.OVER.2.5"));
  assert(compatible("OU.UNDER.3.5", "OU.UNDER.2.5"));
  assert(!compatible("BTTS.NO", "BTTS.YES"));
  assert(compatible("1X2.DRAW", "DC.1X") === false);
  assert(compatible("DC.1X", "1X2.DRAW"));
});

Deno.test("sans recommandation : aucune contrainte, justification inchangée", () => {
  const none = aiPositionOf({ recommandation_possible: false, marches_envisageables: [] });
  assertEquals(none?.recommendation, false);
  assertEquals(contradictions("DC.1X", none), []);
  assertEquals(aiPositionOf(null), null);
  assertEquals(aiJustification("DC.X2", none, "Chiffres."), "Chiffres.");
  assertEquals(aiJustification("DC.X2", genoa, "Chiffres."), "Analyse IA : Genoa attaque mieux. Chiffres.");
  assertEquals(aiJustification("OU.OVER.2.5", genoa, "Chiffres."), "Analyse IA : Match serré. Chiffres.");
});
