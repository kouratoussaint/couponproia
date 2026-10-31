// Tests unitaires du moteur statistique : `deno test supabase/functions/_shared`
import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { buildFiche, formOf, impliedProbabilities, type OddsRow } from "./fiche.ts";
import { evaluate } from "./evaluate.ts";
import { dixonColesMatrix, fitStrengths, runModel2 } from "./poisson2.ts";
import {
  expectedGoals,
  marketProbabilities,
  type PlayedMatch,
  reliabilityFor,
  runModel,
  scoreMatrix,
  tableAt,
} from "./poisson.ts";

const m = (day: number, homeId: number, awayId: number, hg: number, ag: number): PlayedMatch => ({
  kickoffAt: `2024-09-${String(day).padStart(2, "0")}T15:00:00Z`,
  homeId,
  awayId,
  homeGoals: hg,
  awayGoals: ag,
});

Deno.test("matrice des scores : somme 1, probabilités cohérentes", () => {
  const matrix = scoreMatrix(1.6, 1.1);
  const total = matrix.flat().reduce((s, p) => s + p, 0);
  assertAlmostEquals(total, 1, 1e-9);
  const p = marketProbabilities(matrix);
  assertAlmostEquals(p["1X2.HOME"] + p["1X2.DRAW"] + p["1X2.AWAY"], 1, 0.002);
  assertAlmostEquals(p["DC.1X"], p["1X2.HOME"] + p["1X2.DRAW"], 0.002);
  assertAlmostEquals(p["OU.OVER.2.5"] + p["OU.UNDER.2.5"], 1, 0.002);
  assert(p["OU.OVER.0.5"] > p["OU.OVER.1.5"] && p["OU.OVER.1.5"] > p["OU.OVER.2.5"]);
  assert(p["1X2.HOME"] > p["1X2.AWAY"], "λ domicile plus élevé → victoire domicile plus probable");
  // P(0-0) = e^-(λh+λa) (à la troncature près)
  assertAlmostEquals(matrix[0][0], Math.exp(-2.7), 1e-6);
});

Deno.test("sans historique : retour aux moyennes a priori, fiabilité faible", () => {
  const r = runModel([], 1, 2);
  assertEquals(r.lambdaHome, 1.5);
  assertEquals(r.lambdaAway, 1.2);
  assertEquals(r.reliability, "faible");
});

Deno.test("forces : une attaque prolifique augmente λ, avec rétrécissement", () => {
  const history = [m(1, 1, 3, 4, 0), m(2, 1, 4, 3, 1), m(3, 1, 5, 4, 1), m(4, 2, 6, 0, 1)];
  const xg = expectedGoals(history, 1, 2);
  assert(xg.lambdaHome > xg.leagueHome, "l'équipe 1 marque beaucoup à domicile");
  // Rétrécissement : 3 matchs ne suffisent pas à atteindre la moyenne brute (3,67 buts).
  assert(xg.lambdaHome < 3.67);
  assertEquals(xg.homeTeamHomeMatches, 3);
  assertEquals(xg.awayTeamAwayMatches, 0);
});

Deno.test("fiabilité selon le plus petit échantillon", () => {
  assertEquals(reliabilityFor(10, 3), "faible");
  assertEquals(reliabilityFor(5, 9), "moyenne");
  assertEquals(reliabilityFor(8, 12), "bonne");
});

Deno.test("classement recalculé : points, différence de buts", () => {
  const t = tableAt([m(1, 1, 2, 2, 0), m(2, 2, 3, 1, 1), m(3, 3, 1, 0, 0)]);
  assertEquals(t[0], { teamId: 1, rank: 1, played: 2, points: 4, goalDiff: 2, goalsFor: 2 });
  assertEquals(t.map((r) => r.teamId), [1, 3, 2]);
});

Deno.test("forme du plus récent au plus ancien", () => {
  assertEquals(formOf([m(5, 1, 2, 2, 0), m(4, 3, 1, 1, 1), m(3, 4, 1, 3, 0)], 1), "VND");
});

Deno.test("probabilités implicites : marge retirée, groupes incomplets ignorés", () => {
  const o = (market_code: string, outcome_code: string, odd: number, line: number | null = null): OddsRow => ({
    market_code,
    outcome_code,
    line,
    odd_median: odd,
    odd_best: odd,
    bookmakers_count: 5,
    captured_at: "2024-09-01T10:00:00Z",
  });
  const implied = impliedProbabilities([
    o("1X2", "HOME", 2.0), o("1X2", "DRAW", 3.4), o("1X2", "AWAY", 3.8),
    o("OU", "OVER", 1.9, 2.5), o("OU", "UNDER", 1.9, 2.5),
    o("BTTS", "YES", 1.8),
  ]);
  const sum = implied.get("1X2.HOME")! + implied.get("1X2.DRAW")! + implied.get("1X2.AWAY")!;
  assertAlmostEquals(sum, 1, 0.002);
  assert(implied.get("1X2.HOME")! < 0.5, "la marge est retirée (1/2,0 = 0,5 avant normalisation)");
  assertEquals(implied.get("OU.OVER.2.5"), 0.5);
  assertEquals(implied.has("BTTS.YES"), false);
});

Deno.test("fiche : sans fuite du futur, données manquantes signalées", () => {
  const history = [m(1, 1, 3, 2, 0), m(2, 3, 2, 1, 1)];
  const fiche = buildFiche({
    match: {
      id: 99,
      kickoffAt: "2024-09-10T15:00:00Z",
      season: 2024,
      round: "Regular Season - 3",
      competition: { id: 1, name: "Premier League", type: "league" },
      home: { id: 1, name: "Alpha" },
      away: { id: 2, name: "Beta" },
    },
    history,
    recentHome: [{ ...history[0], homeName: "Alpha", awayName: "Gamma" }],
    recentAway: [{ ...history[1], homeName: "Gamma", awayName: "Beta" }],
    headToHead: [],
    odds: [],
    generatedAt: "2024-09-09T00:00:00Z",
  });
  assertEquals(fiche.sample.competition_matches, 2);
  assertEquals(fiche.teams.home.form, "V");
  assertEquals(fiche.teams.away.form, "N");
  assertEquals(fiche.teams.home.standing?.rank, 1);
  assertEquals(fiche.market.available, false);
  assertEquals(fiche.reliability, "faible");
  assert(fiche.missing.some((s) => s.includes("Cotes")));
  assert(fiche.missing.some((s) => s.includes("confrontation")));
  assertEquals(JSON.stringify(fiche).includes("score_final"), false);
});

/** Championnat synthétique : 10 équipes de forces très différentes, 2 matchs aller-retour. */
function syntheticLeague(seed: number): PlayedMatch[] {
  let s = seed;
  const rand = () => (s = (s * 1103515245 + 12345) % 2 ** 31) / 2 ** 31;
  const poisson = (l: number) => {
    let k = 0, p = 1;
    const L = Math.exp(-l);
    do {
      k++;
      p *= rand();
    } while (p > L);
    return k - 1;
  };
  const strength = [2.0, 1.7, 1.4, 1.2, 1.0, 0.9, 0.8, 0.7, 0.6, 0.5];
  const out: PlayedMatch[] = [];
  let day = 0;
  for (let round = 0; round < 4; round++) {
    for (let h = 0; h < 10; h++) {
      for (let a = 0; a < 10; a++) {
        if (h === a) continue;
        day++;
        const kickoffAt = new Date(Date.UTC(2024, 7, 1) + day * 3600_000).toISOString();
        out.push({
          kickoffAt,
          homeId: h + 1,
          awayId: a + 1,
          homeGoals: poisson(1.45 * strength[h] / strength[a] ** 0.5),
          awayGoals: poisson(1.15 * strength[a] / strength[h] ** 0.5),
        });
      }
    }
  }
  return out;
}

Deno.test("évaluation : sur des forces réelles, le modèle bat la fréquence de base", () => {
  const { evaluation, perCompetition } = evaluate([{ name: "Synthétique", matches: syntheticLeague(42) }]);
  assertEquals(evaluation.oneXTwo.matches, 360 - 30);
  assert(
    evaluation.oneXTwo.brierModel < evaluation.oneXTwo.brierBaseline,
    `Brier modèle ${evaluation.oneXTwo.brierModel} ≥ base ${evaluation.oneXTwo.brierBaseline}`,
  );
  assert(evaluation.oneXTwo.loglossModel < evaluation.oneXTwo.loglossBaseline);
  assert(evaluation.calibration.length > 3);
  assertEquals(Object.keys(perCompetition), ["Synthétique"]);
});

Deno.test("fiche : qualité mesurée transmise, marchés faibles signalés", () => {
  const fiche = buildFiche({
    match: {
      id: 1,
      kickoffAt: "2024-09-10T15:00:00Z",
      season: 2024,
      round: null,
      competition: { id: 1, name: "L", type: "cup" },
      home: { id: 1, name: "A" },
      away: { id: 2, name: "B" },
    },
    history: [],
    recentHome: [],
    recentAway: [],
    headToHead: [],
    odds: [],
    generatedAt: "2024-09-09T00:00:00Z",
    quality: { evaluatedMatches: 2210, beatsBaseline: { "1X2": true, OU: false, BTTS: false } },
  });
  assertEquals(fiche.engine_quality?.beats_baseline.OU, false);
  assert(fiche.missing.some((s) => s.includes("OU, BTTS")));
  assertEquals(fiche.teams.home.standing, null, "pas de classement recalculé en coupe");
});

Deno.test("saison précédente pondérée : une équipe dominante n'est plus ramenée à la moyenne", () => {
  // Saison en cours : 2 matchs neutres. Saison précédente : l'équipe 1 écrase tout le monde.
  const current = [m(1, 1, 3, 1, 1), m(2, 4, 2, 1, 1)];
  const lastSeason = Array.from({ length: 10 }, (_, i) => ({
    kickoffAt: `2025-0${(i % 9) + 1}-10T15:00:00Z`, homeId: 1, awayId: 10 + i, homeGoals: 3, awayGoals: 0,
  }));
  const without = runModel(current, 1, 2);
  const withPrior = runModel([...lastSeason.map((x) => ({ ...x, weight: 0.5 })), ...current], 1, 2);
  assert(withPrior.probabilities["1X2.HOME"] > without.probabilities["1X2.HOME"] + 0.1);
  assertEquals(withPrior.sample.homeTeamHomeMatches, 6, "1 match + 10 × 0,5");
});

// ---------------------------------------------------------------------------
// poisson-2.0 (candidat)
// ---------------------------------------------------------------------------

Deno.test("poisson-2.0 : probabilités cohérentes et petits scores corrigés", () => {
  const plain = dixonColesMatrix(1.3, 1.1, 0);
  const dc = dixonColesMatrix(1.3, 1.1, -0.1);
  const sum = dc.flat().reduce((a, b) => a + b, 0);
  assert(Math.abs(sum - 1) < 1e-9, "matrice normalisée");
  assert(dc[0][0] > plain[0][0] && dc[1][1] > plain[1][1], "ρ < 0 : plus de 0-0 et de 1-1");
  assert(dc[1][0] < plain[1][0], "et moins de 1-0");
});

Deno.test("poisson-2.0 : les matchs à l'extérieur comptent, les anciens matchs pèsent moins", () => {
  const day = (d: number) => new Date(Date.UTC(2026, 0, 1) + d * 86400_000).toISOString();
  // L'équipe 1 gagne largement partout, y compris à l'extérieur ; l'équipe 2 perd partout.
  const history = [] as { kickoffAt: string; homeId: number; awayId: number; homeGoals: number; awayGoals: number }[];
  for (let i = 0; i < 10; i++) {
    history.push({ kickoffAt: day(i * 7), homeId: 3 + (i % 4), awayId: 1, homeGoals: 0, awayGoals: 3 });
    history.push({ kickoffAt: day(i * 7 + 1), homeId: 2, awayId: 3 + (i % 4), homeGoals: 0, awayGoals: 2 });
  }
  const s = fitStrengths(history, Date.parse(day(80)));
  assert(s.attack.get(1)! > 1.5, "attaque de l'équipe 1 mesurée sur ses matchs à l'extérieur");
  assert(s.attack.get(2)! < 0.7, "attaque faible de l'équipe 2 mesurée à domicile");
  const r = runModel2(history, 1, 2, day(80));
  assert(r.probabilities["1X2.HOME"] > 0.6, "l'équipe 1 favorite à domicile alors qu'elle n'y a jamais joué");
  // Décroissance : un résultat très ancien pèse moins qu'un résultat récent.
  const old = fitStrengths([{ kickoffAt: day(0), homeId: 1, awayId: 2, homeGoals: 5, awayGoals: 0 }], Date.parse(day(720)));
  const recent = fitStrengths([{ kickoffAt: day(700), homeId: 1, awayId: 2, homeGoals: 5, awayGoals: 0 }], Date.parse(day(720)));
  assert(recent.attack.get(1)! > old.attack.get(1)!, "le match récent pèse davantage");
});
