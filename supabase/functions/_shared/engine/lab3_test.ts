import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { blend, calibrate, fitCalibration, fitGlobalStrengths, fitLeagueStrengths, globalProbabilities, IDENTITY, type LabMatch, marketFromOdds, runExperiment } from "./lab3.ts";
import { DEFAULT_OPTIONS_2, fitStrengths } from "./poisson2.ts";

// Générateur déterministe.
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
          const sh = strength.get(h)!, sa = strength.get(a)!;
          out.push({ id: id++, competitionId: comp, season, kickoffAt: new Date(day).toISOString(), homeId: h, awayId: a,
            homeGoals: poisson(1.5 * sh / sa, r), awayGoals: poisson(1.1 * sa / sh, r) });
        }
      }
      if (round % 3 === 1) {
        const h = 6 + Math.floor(r() * 5), a = 16 + Math.floor(r() * 5);
        const sh = strength.get(h)!, sa = strength.get(a)!;
        const [x, y] = r() < 0.5 ? [h, a] : [a, h];
        out.push({ id: id++, competitionId: 3, season, kickoffAt: new Date(day + 3 * 86400_000).toISOString(), homeId: x, awayId: y,
          homeGoals: poisson(1.4 * (x === h ? sh / sa : sa / sh), r), awayGoals: poisson(1.1 * (x === h ? sa / sh : sh / sa), r) });
      }
    }
  }
  return out;
}

Deno.test("forces globales : une seule compétition = même résultat que poisson-2.0", () => {
  const ms = synthetic().filter((m) => m.competitionId === 1);
  const at = Date.parse("2026-01-01T00:00:00Z");
  const g = fitGlobalStrengths(ms, at);
  const s = fitStrengths(ms, at);
  assertAlmostEquals(g.homeAvg.get(1)!, s.homeAvg, 1e-9);
  for (const t of [1, 5, 10]) {
    assertAlmostEquals(g.attack.get(t)!, s.attack.get(t)!, 1e-9);
    assertAlmostEquals(g.defense.get(t)!, s.defense.get(t)!, 1e-9);
  }
});

Deno.test("forces globales : la coupe relie les championnats", () => {
  const ms = synthetic();
  const g = fitGlobalStrengths(ms, Date.parse("2026-01-01T00:00:00Z"));
  // Le meilleur du championnat 1 est plus fort que le meilleur du championnat 2 (vrai par construction).
  assert(g.attack.get(10)! / g.defense.get(10)! > g.attack.get(20)! / g.defense.get(20)!);
  const p = globalProbabilities(g, 3, 10, 20, DEFAULT_OPTIONS_2);
  assert(p["1X2.HOME"] > p["1X2.AWAY"]);
});

Deno.test("recalibrage : identité, renforcement des favoris, peu de données", () => {
  assertEquals(calibrate([0.5, 0.3, 0.2], IDENTITY).map((x) => Math.round(x * 1000)), [500, 300, 200]);
  const sharp = calibrate([0.6, 0.25, 0.15], { t: 1.3, d: 0 });
  assert(sharp[0] > 0.6);
  assertEquals(fitCalibration([{ p: [0.5, 0.3, 0.2], outcome: 0 }]), IDENTITY);
  // Favoris sous-estimés : l'issue à 60 % annoncés arrive 75 % du temps → T > 1.
  const r = rng(3);
  const samples = Array.from({ length: 2000 }, () => {
    const u = r();
    return { p: [0.6, 0.25, 0.15], outcome: u < 0.75 ? 0 : u < 0.9 ? 1 : 2 };
  });
  assert(fitCalibration(samples).t > 1);
});

Deno.test("marché : marge retirée et mélange", () => {
  const m = marketFromOdds({ home: 2, draw: 3.4, away: 4 })!;
  assertAlmostEquals(m.reduce((a, b) => a + b, 0), 1, 1e-9);
  assertEquals(marketFromOdds({ home: 0, draw: 3, away: 3 }), null);
  assertEquals(blend([0.5, 0.3, 0.2], [0.3, 0.3, 0.4], 0.5).map((x) => Math.round(x * 100)), [40, 30, 30]);
});

Deno.test("expérience complète : mêmes matchs, B ≥ A quand les compétitions sont reliées", () => {
  const all = synthetic();
  const groups = [1, 2, 3].flatMap((c) => [2025].map((s) => ({
    key: `${c}:${s}`, competitionId: c, season: s,
    matches: all.filter((m) => m.competitionId === c && m.season === s),
    prior: all.filter((m) => m.competitionId === c && m.season === s - 1).map((m) => ({ ...m, weight: 0.5 })),
  })));
  const t0 = performance.now();
  const r = runExperiment(groups, all, new Map(), 10, undefined, { leagues: new Set([1, 2]) });
  const ms = performance.now() - t0;
  assert(r.matches > 100);
  assertEquals(r.oneXTwo.A.matches, r.oneXTwo.B.matches);
  assert(r.oneXTwo.A.logloss < r.oneXTwo.baseline.logloss);
  // Sur la coupe, connaître les championnats aide nettement.
  const cup = r.per_competition_logloss["3:2025"];
  if (cup) assert(cup.B <= cup.A + 0.02, JSON.stringify(cup));
  console.log(`expérience synthétique : ${r.matches} matchs en ${Math.round(ms)} ms`);
});

Deno.test("variante C : championnat seul = B ; niveau du championnat le plus fort > 1", () => {
  const all = synthetic();
  const at = Date.parse("2026-01-01T00:00:00Z");
  const one = all.filter((m) => m.competitionId === 1);
  // C fait 4 itérations de plus (niveau des championnats) : B réglé pareil pour comparer.
  const b = fitGlobalStrengths(one, at, { ...DEFAULT_OPTIONS_2, iterations: DEFAULT_OPTIONS_2.iterations + 4 });
  const c = fitLeagueStrengths(one, at, new Set([1]));
  for (const t of [1, 5, 10]) assertAlmostEquals(c.attack.get(t)!, b.attack.get(t)!, 1e-9);
  // Les deux championnats + la coupe : le championnat 1 (plus fort par construction) a S > 1.
  const lv = fitLeagueStrengths(all, at, new Set([1, 2])).leagueLevel;
  assert(lv.get(1)! > lv.get(2)!, JSON.stringify([...lv]));
});

Deno.test("variante C : un club dominant d'un championnat faible n'est pas surestimé en coupe", () => {
  const all = synthetic();
  const at = Date.parse("2026-01-01T00:00:00Z");
  const b = fitGlobalStrengths(all, at);
  const c = fitLeagueStrengths(all, at, new Set([1, 2]));
  // Meilleur club du championnat 2 (le plus faible) contre un club moyen du championnat 1.
  const pb = globalProbabilities(b, 3, 20, 6), pc = globalProbabilities(c, 3, 20, 6);
  assert(pc["1X2.HOME"] < pb["1X2.HOME"], `${pc["1X2.HOME"]} < ${pb["1X2.HOME"]}`);
});

Deno.test("variante C : équipe d'une seule compétition (coupe) = poisson-2.0 à l'identique", () => {
  const all = synthetic();
  const at = Date.parse("2026-01-01T00:00:00Z");
  // Coupe seule, sans championnat suivi pour ses équipes : C doit se ramener à A.
  const cup = all.filter((m) => m.competitionId === 3);
  const a = fitStrengths(cup, at, { ...DEFAULT_OPTIONS_2, iterations: DEFAULT_OPTIONS_2.iterations + 4 });
  const c = fitLeagueStrengths(cup, at, new Set([1, 2]));
  for (const t of [6, 8, 16]) {
    if (!a.attack.has(t)) continue;
    assertAlmostEquals(c.attack.get(t)!, a.attack.get(t)!, 1e-9);
    assertAlmostEquals(c.defense.get(t)!, a.defense.get(t)!, 1e-9);
  }
});
