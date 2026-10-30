// Tests des règles de règlement : `deno test supabase/functions/_shared`
import { assertEquals } from "jsr:@std/assert@1";
import { couponResult, type MatchState, outcomeWins, selectionResult } from "./settle.ts";

const NOW = new Date("2026-11-02T12:00:00Z");
const m = (p: Partial<MatchState>): MatchState => ({
  status: "finished",
  statusShort: "FT",
  kickoffAt: "2026-11-01T15:00:00Z",
  homeGoals: 2,
  awayGoals: 1,
  ftHomeGoals: null,
  ftAwayGoals: null,
  ...p,
});

Deno.test("marchés : 1X2, double chance, plus/moins, les deux marquent", () => {
  assertEquals(outcomeWins("1X2.HOME", 2, 1), true);
  assertEquals(outcomeWins("1X2.DRAW", 1, 1), true);
  assertEquals(outcomeWins("DC.X2", 1, 1), true);
  assertEquals(outcomeWins("DC.12", 1, 1), false);
  assertEquals(outcomeWins("OU.OVER.2.5", 2, 1), true);
  assertEquals(outcomeWins("OU.UNDER.1.5", 1, 0), true);
  assertEquals(outcomeWins("OU.OVER.0.5", 0, 0), false);
  assertEquals(outcomeWins("BTTS.YES", 2, 0), false);
  assertEquals(outcomeWins("BTTS.NO", 0, 0), true);
  assertEquals(outcomeWins("XYZ.A", 1, 0), null);
});

Deno.test("score à 90 minutes : prolongations et tirs au but ignorés", () => {
  // 1-1 à 90 min, 2-1 après prolongation : « nul » gagne, « victoire domicile » perd.
  const aet = m({ statusShort: "AET", homeGoals: 2, awayGoals: 1, ftHomeGoals: 1, ftAwayGoals: 1 });
  assertEquals(selectionResult("1X2.DRAW", aet, NOW), "won");
  assertEquals(selectionResult("1X2.HOME", aet, NOW), "lost");
  // Prolongation sans score à 90 min connu : en attente (pas de règlement sur un score incertain).
  assertEquals(selectionResult("1X2.HOME", m({ statusShort: "PEN" }), NOW), "pending");
});

Deno.test("cas particuliers : reporté, interrompu, annulé, attribué, en cours", () => {
  assertEquals(selectionResult("1X2.HOME", m({ status: "postponed", kickoffAt: "2026-11-02T10:00:00Z" }), NOW), "pending");
  assertEquals(selectionResult("1X2.HOME", m({ status: "postponed", kickoffAt: "2026-10-30T10:00:00Z" }), NOW), "void");
  assertEquals(selectionResult("1X2.HOME", m({ status: "interrupted", kickoffAt: "2026-10-29T10:00:00Z" }), NOW), "void");
  assertEquals(selectionResult("1X2.HOME", m({ status: "cancelled" }), NOW), "void");
  assertEquals(selectionResult("1X2.HOME", m({ status: "awarded" }), NOW), "void");
  assertEquals(selectionResult("1X2.HOME", m({ status: "live" }), NOW), "pending");
});

Deno.test("coupon : perdu dès une sélection perdue, void à 1,00, tout annulé", () => {
  assertEquals(couponResult([{ result: "won", odd: 1.8 }, { result: "lost", odd: 2 }, { result: "pending", odd: 1.5 }]),
    { result: "lost", settledOdd: 0 });
  assertEquals(couponResult([{ result: "won", odd: 1.8 }, { result: "pending", odd: 2 }]), { result: "pending", settledOdd: null });
  assertEquals(couponResult([{ result: "won", odd: 1.8 }, { result: "void", odd: 2 }, { result: "won", odd: 1.5 }]),
    { result: "won", settledOdd: 2.7 });
  assertEquals(couponResult([{ result: "void", odd: 1.8 }, { result: "void", odd: 2 }]), { result: "void", settledOdd: 1 });
});
