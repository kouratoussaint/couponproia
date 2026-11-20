import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { combineEvaluation3, evaluate3, evaluate3Part, planEvaluation3 } from "./evaluate.ts";

function rng(seed: number) {
  return () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
}
function poisson(l: number, r: () => number) {
  let k = 0, p = Math.exp(-l), s = p;
  const u = r();
  while (u > s && k < 10) { k++; p *= l / k; s += p; }
  return k;
}
/** Quatre championnats de 10 équipes sur deux saisons, journées à des jours différents. */
function data() {
  const r = rng(5);
  const all: { competitionId: number; season: number; kickoffAt: string; homeId: number; awayId: number; homeGoals: number; awayGoals: number }[] = [];
  const start = Date.parse("2024-08-01T15:00:00Z");
  for (const season of [2024, 2025]) {
    for (let round = 0; round < 30; round++) {
      for (let c = 1; c <= 4; c++) {
        const teams = Array.from({ length: 10 }, (_, i) => c * 100 + i).sort(() => r() - 0.5);
        const day = start + ((season - 2024) * 365 + round * 7 + c) * 86400_000;
        for (let k = 0; k < 10; k += 2) {
          all.push({ competitionId: c, season, kickoffAt: new Date(day).toISOString(), homeId: teams[k], awayId: teams[k + 1], homeGoals: poisson(1.5, r), awayGoals: poisson(1.1, r) });
        }
      }
    }
  }
  const groups = [1, 2, 3, 4].flatMap((c) => [2024, 2025].map((s) => ({ name: `${c}:${s}`, competitionId: c, matches: all.filter((m) => m.competitionId === c && m.season === s) })));
  return { all, groups };
}

Deno.test("évaluation découpée en lots = évaluation d'un seul tenant", () => {
  const { all, groups } = data();
  const leagues = new Set([1, 2, 3, 4]);
  const whole = evaluate3(groups, all, leagues);
  const plan = planEvaluation3(groups, 40);
  assert(plan.length >= 3, `plusieurs lots attendus (${plan.length})`);
  assertEquals(plan.flat().sort(), groups.map((g) => g.name).filter((n) => plan.flat().includes(n)).sort());
  // Chaque lot passe par le JSON, comme entre deux appels du serveur.
  const parts = plan.map((names) => JSON.parse(JSON.stringify(evaluate3Part(groups.filter((g) => names.includes(g.name)), all, leagues))));
  const split = combineEvaluation3(parts);
  assertEquals(split.evaluation.oneXTwo.matches, whole.evaluation.oneXTwo.matches);
  assertAlmostEquals(split.evaluation.oneXTwo.loglossModel, whole.evaluation.oneXTwo.loglossModel, 1e-3);
  assertAlmostEquals(split.evaluation.over25.brierModel, whole.evaluation.over25.brierModel, 1e-3);
  assertEquals(Object.keys(split.perCompetition).sort(), Object.keys(whole.perCompetition).sort());
  assertEquals(split.evaluation.engineVersion, "poisson-3.0");
});

Deno.test("plan : une compétition-saison n'est jamais coupée, aucune n'est oubliée", () => {
  const { groups } = data();
  const plan = planEvaluation3(groups, 1);
  // Lot minimal : une compétition-saison par lot, même au-delà de la limite.
  for (const lot of plan) assertEquals(lot.length, 1);
  assertEquals(planEvaluation3(groups, 10_000).length, 1);
});
