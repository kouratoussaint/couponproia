// Tests unitaires : `deno test supabase/functions/_shared`
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { ApiFootballError, ApiFootballProvider, parseFixture, parseOdds, parseStandings } from "./api_football.ts";
import { normalizeBet, normalizeStatus, safeEqual, summarizeOdds } from "./normalize.ts";

Deno.test("statuts : codes du fournisseur ramenés à nos statuts", () => {
  assertEquals(normalizeStatus("NS"), "scheduled");
  assertEquals(normalizeStatus("2H"), "live");
  assertEquals(normalizeStatus("HT"), "live");
  assertEquals(normalizeStatus("FT"), "finished");
  assertEquals(normalizeStatus("PEN"), "finished");
  assertEquals(normalizeStatus("PST"), "postponed");
  assertEquals(normalizeStatus("SUSP"), "interrupted");
  assertEquals(normalizeStatus("XYZ"), "unknown");
  assertEquals(normalizeStatus(null), "unknown");
});

Deno.test("marchés : 1X2, double chance, plus/moins, les deux marquent", () => {
  assertEquals(normalizeBet("Match Winner", "Home"), { market: "1X2", outcome: "HOME", line: null });
  assertEquals(normalizeBet("Double Chance", "Draw/Away"), { market: "DC", outcome: "X2", line: null });
  assertEquals(normalizeBet("Goals Over/Under", "Over 2.5"), { market: "OU", outcome: "OVER", line: 2.5 });
  assertEquals(normalizeBet("Goals Over/Under", "Under 1.5"), { market: "OU", outcome: "UNDER", line: 1.5 });
  assertEquals(normalizeBet("Goals Over/Under", "Over 6.5"), null);
  assertEquals(normalizeBet("Both Teams Score", "Yes"), { market: "BTTS", outcome: "YES", line: null });
  assertEquals(normalizeBet("Corners Over Under", "Over 9.5"), null);
});

Deno.test("résumé des cotes : médiane, meilleure cote, un vote par bookmaker, valeurs aberrantes écartées", () => {
  const q = (bookmaker: string, odd: number) => ({ bookmaker, market: "1X2", outcome: "HOME", line: null, odd });
  const [s] = summarizeOdds([q("A", 1.8), q("B", 2.0), q("C", 2.2), q("D", 1.9), q("A", 9.9), q("E", 0.5), q("F", NaN)]);
  assertEquals(s.count, 4);
  assertEquals(s.median, 1.95);
  assertEquals(s.best, 2.2);
});

Deno.test("comparaison de secrets", () => {
  assertEquals(safeEqual("abc", "abc"), true);
  assertEquals(safeEqual("abc", "abd"), false);
  assertEquals(safeEqual("abc", "abcd"), false);
});

const fixtureJson = {
  fixture: {
    id: 1001,
    referee: "M. Arbitre",
    date: "2026-11-01T15:00:00+00:00",
    venue: { name: "Stade" },
    status: { short: "2H", elapsed: 67 },
  },
  league: { id: 39, season: 2026, round: "Regular Season - 10" },
  teams: { home: { id: 1, name: "Alpha", logo: "https://x/1.png" }, away: { id: 2, name: "Beta", logo: null } },
  goals: { home: 2, away: 1 },
  score: { halftime: { home: 1, away: 0 }, fulltime: { home: 2, away: 1 } },
};

Deno.test("lecture d'un match API-Football", () => {
  const f = parseFixture(fixtureJson);
  assertEquals(f.ref, "1001");
  assertEquals(f.leagueRef, "39");
  assertEquals(f.status, "live");
  assertEquals(f.elapsed, 67);
  assertEquals(f.home.name, "Alpha");
  assertEquals(f.away.logoUrl, null);
  assertEquals([f.homeGoals, f.awayGoals, f.htHomeGoals, f.htAwayGoals, f.ftHomeGoals, f.ftAwayGoals], [2, 1, 1, 0, 2, 1]);
});

Deno.test("lecture d'un classement en groupes", () => {
  const rows = parseStandings({
    league: {
      standings: [[
        { rank: 1, team: { id: 1, name: "Alpha" }, points: 9, goalsDiff: 5, group: "Groupe A", form: "WWW",
          all: { played: 3, win: 3, draw: 0, lose: 0, goals: { for: 7, against: 2 } } },
      ], [
        { rank: 1, team: { id: 3, name: "Gamma" }, points: 7, goalsDiff: 3, group: "Groupe B",
          all: { played: 3, win: 2, draw: 1, lose: 0, goals: { for: 5, against: 2 } } },
      ]],
    },
  });
  assertEquals(rows.length, 2);
  assertEquals(rows[1].group, "Groupe B");
  assertEquals(rows[0].goalsFor, 7);
});

Deno.test("lecture des cotes : seuls les marchés suivis sont gardés", () => {
  const quotes = parseOdds({
    bookmakers: [{
      name: "Book",
      bets: [
        { name: "Match Winner", values: [{ value: "Home", odd: "1.90" }, { value: "Draw", odd: "3.40" }] },
        { name: "Exact Score", values: [{ value: "1:0", odd: "7.00" }] },
      ],
    }],
  });
  assertEquals(quotes.length, 2);
  assertEquals(quotes[0], { bookmaker: "Book", market: "1X2", outcome: "HOME", line: null, odd: 1.9 });
});

function fakeFetch(body: unknown, headers: Record<string, string> = {}, status = 200): typeof fetch {
  return (() => Promise.resolve(new Response(JSON.stringify(body), { status, headers }))) as typeof fetch;
}

Deno.test("fournisseur : quota restant lu dans les en-têtes, requêtes comptées", async () => {
  const p = new ApiFootballProvider("k", fakeFetch({ errors: [], response: [fixtureJson] }, { "x-ratelimit-requests-remaining": "42" }));
  const list = await p.getFixtures("39", 2026);
  assertEquals(list.length, 1);
  assertEquals(p.requestsUsed, 1);
  assertEquals(p.requestsRemaining, 42);
});

Deno.test("fournisseur : une erreur de l'API (ex. saison hors offre) est remontée", async () => {
  const p = new ApiFootballProvider("k", fakeFetch({ errors: { plan: "Free plans do not have access to this season" }, response: [] }));
  await assertRejects(() => p.getFixtures("39", 2026), ApiFootballError, "Free plans");
});

Deno.test("fournisseur : erreur HTTP remontée", async () => {
  const p = new ApiFootballProvider("k", fakeFetch({}, {}, 500));
  await assertRejects(() => p.getStandings("39", 2026), ApiFootballError, "HTTP 500");
});

Deno.test("fournisseur : sur HTTP 429, attend puis réessaie une fois", async () => {
  const responses = [
    new Response("{}", { status: 429 }),
    new Response(JSON.stringify({ errors: [], response: [fixtureJson] }), { status: 200 }),
  ];
  const waits: number[] = [];
  const p = new ApiFootballProvider(
    "k",
    (() => Promise.resolve(responses.shift()!)) as typeof fetch,
    (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
    7000,
  );
  const list = await p.getFixtures("39", 2024);
  assertEquals(list.length, 1);
  assertEquals(p.requestsUsed, 2);
  assertEquals(waits.includes(7000), true);
});

Deno.test("fournisseur : espacement minimal entre deux requêtes", async () => {
  const waits: number[] = [];
  const p = new ApiFootballProvider(
    "k",
    fakeFetch({ errors: [], response: [] }),
    (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
  );
  p.configure({ minIntervalMs: 6500 });
  await p.getFixtures("39", 2024);
  await p.getFixtures("39", 2024);
  assertEquals(waits.length, 1);
  assertEquals(waits[0] > 6000, true);
});
