import { assert, assertAlmostEquals, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { fitLeagueStrengths, type LabMatch } from "./lab3.ts";
import { DEFAULT_OPTIONS_3, fromSnapshot, LeagueModel, runModel3, strengthsAt, toSnapshot } from "./poisson3.ts";
import { DEFAULT_OPTIONS_2, fitStrengths } from "./poisson2.ts";

function rng(seed: number) {
  return () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
}
function poisson(l: number, r: () => number) {
  let k = 0, p = Math.exp(-l), s = p;
  const u = r();
  while (u > s && k < 10) { k++; p *= l / k; s += p; }
  return k;
}
/** Deux championnats de 10 équipes et une coupe entre leurs meilleurs, sur deux saisons. */
function synthetic(seed = 7) {
  const r = rng(seed);
  const strength = new Map<number, number>();
  for (let t = 1; t <= 20; t++) strength.set(t, t <= 10 ? 0.7 + t * 0.06 : 0.5 + (t - 10) * 0.05);
  const out: LabMatch[] = [];
  let id = 1;
  const start = Date.parse("2024-08-01T15:00:00Z");
  for (const season of [2024, 2025]) {
    for (let round = 0; round < 30; round++) {
      const day = start + ((season - 2024) * 365 + round * 7) * 86400_000;
      for (const [comp, teams] of [[1, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]], [2, [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]]] as const) {
        const order = [...teams].sort(() => r() - 0.5);
        for (let k = 0; k < order.length; k += 2) {
          const h = order[k], a = order[k + 1];
          out.push({ id: id++, competitionId: comp, season, kickoffAt: new Date(day).toISOString(), homeId: h, awayId: a,
            homeGoals: poisson(1.5 * strength.get(h)! / strength.get(a)!, r), awayGoals: poisson(1.1 * strength.get(a)! / strength.get(h)!, r) });
        }
      }
      if (round % 3 === 1) {
        const h = 6 + Math.floor(r() * 5), a = 16 + Math.floor(r() * 5);
        const [x, y] = r() < 0.5 ? [h, a] : [a, h];
        out.push({ id: id++, competitionId: 3, season, kickoffAt: new Date(day + 3 * 86400_000).toISOString(), homeId: x, awayId: y,
          homeGoals: poisson(1.4 * strength.get(x)! / strength.get(y)!, r), awayGoals: poisson(1.1 * strength.get(y)! / strength.get(x)!, r) });
      }
    }
  }
  return out;
}
// Après le dernier match des données (les calculs de référence ne filtrent pas les dates).
const AT = Date.parse("2026-06-01T00:00:00Z");
const LEAGUES = new Set([1, 2]);
/** Précision stricte pour les comparaisons exactes (le réglage par défaut s'arrête à 0,01 %). */
const STRICT = { ...DEFAULT_OPTIONS_3, tolerance: 1e-10, maxIterations: 5000 };

Deno.test("poisson-3.0 = variante C du laboratoire (calcul mené jusqu'au point fixe)", () => {
  const all = synthetic();
  const lab = fitLeagueStrengths(all, AT, LEAGUES, { ...DEFAULT_OPTIONS_2, iterations: 600 });
  const s = strengthsAt(all, AT, LEAGUES, STRICT);
  for (const t of [1, 6, 10, 11, 16, 20]) {
    assertAlmostEquals(s.attack.get(t)!, lab.attack.get(t)!, 1e-5);
    assertAlmostEquals(s.defense.get(t)!, lab.defense.get(t)!, 1e-5);
  }
  assertAlmostEquals(s.leagueLevel.get(1)!, lab.leagueLevel.get(1)!, 1e-3);
  assertAlmostEquals(s.homeAvg.get(3)!, lab.homeAvg.get(3)!, 1e-9);
});

Deno.test("calcul repris jour après jour = calcul complet", () => {
  const all = synthetic().sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));
  const model = new LeagueModel(LEAGUES, STRICT);
  let i = 0;
  for (const day of ["2025-03-01", "2025-06-01", "2025-11-01"]) {
    const at = Date.parse(`${day}T00:00:00Z`);
    while (i < all.length && Date.parse(all[i].kickoffAt) < at) model.add(all[i++]);
    const warm = model.solve(at);
    const cold = strengthsAt(all, at, LEAGUES, STRICT);
    for (const t of [2, 9, 13, 19]) assertAlmostEquals(warm.attack.get(t)!, cold.attack.get(t)!, 1e-5);
  }
});

Deno.test("une seule compétition : poisson-2.0 (au point fixe)", () => {
  const one = synthetic().filter((m) => m.competitionId === 1);
  const a = fitStrengths(one, AT, { ...DEFAULT_OPTIONS_2, iterations: 600 });
  const s = strengthsAt(one, AT, new Set([1]), STRICT);
  for (const t of [1, 5, 10]) {
    assertAlmostEquals(s.attack.get(t)!, a.attack.get(t)!, 1e-5);
    assertAlmostEquals(s.defense.get(t)!, a.defense.get(t)!, 1e-5);
  }
});

Deno.test("prédiction, photo enregistrée et ordre des matchs", () => {
  const s = strengthsAt(synthetic(), AT, LEAGUES);
  const m = runModel3(s, 3, 10, 20);
  const sum = m.probabilities["1X2.HOME"] + m.probabilities["1X2.DRAW"] + m.probabilities["1X2.AWAY"];
  assertAlmostEquals(sum, 1, 3e-3); // probabilités arrondies au millième
  assert(m.probabilities["1X2.HOME"] > m.probabilities["1X2.AWAY"], "le meilleur du championnat fort reçoit");
  const back = runModel3(fromSnapshot(JSON.parse(JSON.stringify(toSnapshot(s)))), 3, 10, 20);
  assertAlmostEquals(back.probabilities["1X2.HOME"], m.probabilities["1X2.HOME"], 1e-4);
  assertEquals(runModel3(s, 99, 999, 998).reliability, "faible");
  const model = new LeagueModel(LEAGUES);
  model.add({ competitionId: 1, kickoffAt: "2025-01-02T00:00:00Z", homeId: 1, awayId: 2, homeGoals: 1, awayGoals: 0 });
  assertThrows(() => model.add({ competitionId: 1, kickoffAt: "2025-01-01T00:00:00Z", homeId: 1, awayId: 2, homeGoals: 1, awayGoals: 0 }));
  assertEquals(DEFAULT_OPTIONS_3.leagueShrink, 10);
});

Deno.test("réglage par défaut : à moins d'un millième du point fixe", () => {
  const all = synthetic();
  const exact = strengthsAt(all, AT, LEAGUES, STRICT);
  const fast = strengthsAt(all, AT, LEAGUES);
  for (const t of [1, 6, 10, 11, 16, 20]) {
    assertAlmostEquals(fast.attack.get(t)! / exact.attack.get(t)!, 1, 1e-3);
    assertAlmostEquals(fast.defense.get(t)! / exact.defense.get(t)!, 1, 1e-3);
  }
  const p = runModel3(fast, 3, 10, 20).probabilities["1X2.HOME"], q = runModel3(exact, 3, 10, 20).probabilities["1X2.HOME"];
  assertAlmostEquals(p, q, 2e-3);
});
