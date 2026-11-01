// Tests : lecture des chiffres et mots-clés d'une demande, priorité sur la compréhension de l'IA.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { describeRequest, extractConstraints, reconcileIntent } from "./keywords.ts";
import type { Intent } from "./intent.ts";

const NOW = new Date("2026-11-01T08:00:00Z"); // dimanche
const TZ = "Africa/Ouagadougou";
const x = (m: string) => extractConstraints(m, NOW, TZ);

const base: Intent = {
  intent: "creer_coupon", jour: null, competitions: [], equipes: [], exclure_equipes: [],
  nombre_selections: null, cote_totale_cible: null, cote_totale_min: null, cote_totale_max: null,
  cote_selection_min: null, cote_selection_max: null, marches: [], issues: [], risque: null,
  nombre_coupons: null, retirer_positions: [], remplacer_plus_fragiles: 0, ajouter: 0, reponse: "",
};

Deno.test("chiffres : sélections, cote totale cible, plage, minimum, maximum", () => {
  const a = x("Fais-moi un coupon de 3 matchs avec une cote totale proche de 4");
  assertEquals(a.nombre_selections, 3);
  assertEquals(a.cote_totale_cible, 4);
  const b = x("coupon de quatre sélections, côte entre 5 et 8 pour demain");
  assertEquals(b.nombre_selections, 4);
  assertEquals([b.cote_totale_min, b.cote_totale_max], [5, 8]);
  assertEquals(b.jour, "demain");
  assertEquals(x("cote d'au moins 2,5").cote_totale_min, 2.5);
  assertEquals(x("cote totale max 3").cote_totale_max, 3);
  assertEquals(x("je veux une cote de 10").cote_totale_cible, 10);
});

Deno.test("cote par sélection distincte de la cote totale", () => {
  const a = x("5 matchs avec une cote par match entre 1,3 et 1,6, cote totale 6");
  assertEquals([a.cote_selection_min, a.cote_selection_max], [1.3, 1.6]);
  assertEquals(a.cote_totale_cible, 6);
  const b = x("cote de 1.5 par match");
  assertEquals([b.cote_selection_min, b.cote_selection_max], [1.35, 1.65]);
  assertEquals(b.cote_totale_cible, null);
});

Deno.test("marchés : double chance, buts, les deux marquent, nul", () => {
  assertEquals(x("en double chance").marches, ["DC"]);
  assertEquals(x("plus de 2,5 buts").issues, ["OU.OVER.2.5"]);
  assertEquals(x("plus de 2 buts").issues, ["OU.OVER.2.5"]);
  assertEquals(x("moins de 3 buts").issues, ["OU.UNDER.2.5"]);
  assertEquals(x("les deux équipes marquent").issues, ["BTTS.YES"]);
  assertEquals(x("un match nul").issues, ["1X2.DRAW"]);
  assert(!x("coupon de 3 matchs").mentionsMarket);
});

Deno.test("jours : aujourd'hui, demain, après-demain, week-end, jour de semaine, date", () => {
  assertEquals(x("ce soir").jour, "aujourdhui");
  assertEquals(x("après-demain").jour, "2026-11-03");
  assertEquals(x("ce week-end").jour, "week_end");
  assertEquals(x("samedi").jour, "2026-11-07");
  assertEquals(x("le 5/11").jour, "2026-11-05");
});

Deno.test("l'IA ne peut rien ajouter : chiffres du message prioritaires, ajouts retirés", () => {
  const ai: Intent = {
    ...base, nombre_selections: 4, cote_totale_cible: 5, jour: "demain",
    marches: ["OU"], issues: ["OU.OVER.2.5"], risque: "audacieux", equipes: ["Arsenal", "Real Madrid"],
  };
  const { intent, dropped } = reconcileIntent(ai, "3 matchs avec Arsenal, cote 4", NOW, TZ);
  assertEquals(intent.nombre_selections, 3, "chiffre du message");
  assertEquals(intent.cote_totale_cible, 4);
  assertEquals(intent.jour, null, "jour non demandé");
  assertEquals(intent.issues, []);
  assertEquals(intent.risque, null);
  assertEquals(intent.equipes, ["Arsenal"], "équipe absente du message retirée");
  assert(dropped.includes("jour") && dropped.includes("marches") && dropped.includes("equipes"));
});

Deno.test("trois versions demandées : variantes", () => {
  const { intent } = reconcileIntent(base, "donne-moi 3 coupons de 2 matchs", NOW, TZ);
  assertEquals(intent.intent, "variantes");
  assertEquals(intent.nombre_coupons, 3);
  assertEquals(intent.nombre_selections, 2);
});

Deno.test("rappel de la demande comprise", () => {
  const s = describeRequest({ ...base, nombre_selections: 3, cote_totale_cible: 4, competitions: ["Premier League"] }, "demain");
  assertEquals(s, "Demande comprise : demain · 3 sélections · cote totale proche de 4 · Premier League.");
});
