import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { weeklyEmail } from "./weekly_mail.ts";

const since = new Date("2026-10-26T07:05:00Z");
const until = new Date("2026-11-02T07:05:00Z");
const forbidden = /(^|[^a-zà-ÿ])(sûr(e|s|es)?|sûrement|garanti\w*|assuré\w*|certitudes?|imparables?|infaillibles?|sans risque|gains?)([^a-zà-ÿ]|$)/i;

Deno.test("rapport hebdomadaire : bilan complet, pertes comprises", () => {
  const m = weeklyEmail(
    {
      user_id: "u", email: "a@b.c", name: "Toussaint",
      mine: { won: 2, lost: 1, void: 0 },
      journal: { bets: 4, won: 2, lost: 2, staked: 4000, returned: 3500 },
    },
    { won: 7, lost: 5, void: 1, avg_won_odd: 2.1 },
    since, until,
  );
  assertEquals(m.subject, "Votre semaine Coupon Pro IA (du 26/10 au 02/11)");
  assertStringIncludes(m.text, "Bonjour Toussaint,");
  assertStringIncludes(m.text, "3 coupons décidés : 2 gagnés, 1 perdu.");
  assertStringIncludes(m.text, "4 paris réglés : 2 passés, 2 perdus.");
  assertStringIncludes(m.text, "Mises : 4 000 FCFA · Retour : 3 500 FCFA · Bilan net : −500 FCFA.");
  assertStringIncludes(m.text, "13 coupons décidés : 7 gagnés, 5 perdus, 1 annulé (réussite 58 %, annulés exclus).");
  assertStringIncludes(m.text, "Cote moyenne des coupons gagnés : 2,10.");
  assertStringIncludes(m.text, "Pour l'arrêter");
  assert(!forbidden.test(m.text), "aucun mot interdit");
});

Deno.test("rapport hebdomadaire : semaine sans activité", () => {
  const m = weeklyEmail(
    { user_id: "u", email: "a@b.c", name: "", mine: { won: 0, lost: 0, void: 0 }, journal: { bets: 0, won: 0, lost: 0, staked: 0, returned: 0 } },
    { won: 0, lost: 0, void: 0, avg_won_odd: null },
    since, until, "XOF",
  );
  assertStringIncludes(m.text, "Bonjour,");
  assertStringIncludes(m.text, "Aucun de vos coupons enregistrés n'a été décidé cette semaine.");
  assertStringIncludes(m.text, "Aucun pari réglé cette semaine");
  assertStringIncludes(m.text, "Aucun coupon de la plateforme décidé cette semaine.");
  assert(!m.text.includes("Cote moyenne"));
});

Deno.test("rapport hebdomadaire en anglais (profil English)", () => {
  const m = weeklyEmail(
    {
      user_id: "u", email: "a@b.c", name: "Sam", locale: "en",
      mine: { won: 1, lost: 1, void: 0 },
      journal: { bets: 2, won: 1, lost: 1, staked: 12000, returned: 15500 },
    },
    { won: 7, lost: 5, void: 1, avg_won_odd: 2.1 },
    since, until,
  );
  assertEquals(m.subject, "Your Coupon Pro IA week (26/10 to 02/11)");
  assertStringIncludes(m.text, "Hello Sam,");
  assertStringIncludes(m.text, "2 coupons decided: 1 won, 1 lost.");
  assertStringIncludes(m.text, "Stakes: 12,000 FCFA · Return: 15,500 FCFA · Net result: +3,500 FCFA.");
  assertStringIncludes(m.text, "13 coupons decided: 7 won, 5 lost, 1 void (success 58%, void excluded).");
  assertStringIncludes(m.text, "Average odd of winning coupons: 2.10.");
  assert(!/guarantee|winnings|sure bet|risk-free/i.test(m.text), "no forbidden words");
});
