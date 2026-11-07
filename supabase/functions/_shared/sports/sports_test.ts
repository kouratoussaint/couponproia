// Tests unitaires : `deno test supabase/functions/_shared`
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  ApiFootballError,
  ApiFootballProvider,
  parseAbsence,
  parseFixture,
  parseLineups,
  parseOdds,
  parseStandings,
} from "./api_football.ts";
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

Deno.test("compositions : lues seulement quand elles sont publiées", () => {
  assertEquals(parseLineups(undefined), []);
  assertEquals(parseLineups([{ team: { id: 33, name: "A" }, formation: "4-3-3", startXI: [] }]), []);
  const l = parseLineups([{
    team: { id: 33, name: "Manchester United", logo: "https://x/33.png" },
    coach: { id: 1, name: "R. Amorim" },
    formation: "3-4-2-1",
    startXI: [{ player: { id: 1, name: "A. Onana", number: 24, pos: "G", grid: "1:1" } }, { player: { name: "" } }],
    substitutes: [{ player: { id: 2, name: "T. Heaton", number: 22, pos: "G" } }],
  }]);
  assertEquals(l.length, 1);
  assertEquals(l[0].team.ref, "33");
  assertEquals(l[0].formation, "3-4-2-1");
  assertEquals(l[0].coach, "R. Amorim");
  assertEquals(l[0].startXI, [{ name: "A. Onana", number: 24, pos: "G" }]);
  assertEquals(l[0].substitutes.length, 1);
});

Deno.test("absents : joueur, équipe, type et motif", () => {
  const a = parseAbsence({
    player: { id: 9, name: "L. Shaw", type: "Missing Fixture", reason: "Muscle Injury" },
    team: { id: 33, name: "Manchester United" },
    fixture: { id: 1208021 },
  });
  assertEquals(a, {
    fixtureRef: "1208021",
    team: { ref: "33", name: "Manchester United", logoUrl: null },
    player: "L. Shaw",
    type: "Missing Fixture",
    reason: "Muscle Injury",
  });
  assertEquals(parseAbsence({ player: { name: "X" }, team: { id: 1 } }), null, "sans match : ignoré");
  assertEquals(parseAbsence({ player: {}, team: { id: 1 }, fixture: { id: 2 } }), null, "sans nom : ignoré");
});

// --- LOT 25 : catalogue et matchs des coupons non réglés -----------------------
import { parseCatalogLeague } from "./api_football.ts";
import { SportsSync } from "./sync.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { CatalogLeague, SportsDataProvider } from "./types.ts";

Deno.test("catalogue : saisons et couverture de la saison en cours", () => {
  const l = parseCatalogLeague({
    league: { id: 423, name: "Ligue 1", type: "League", logo: "x.png" },
    country: { name: "Burkina-Faso", code: "BF" },
    seasons: [
      { year: 2024, current: false, coverage: { odds: false } },
      {
        year: 2025,
        current: true,
        coverage: { odds: true, injuries: false, standings: true, fixtures: { lineups: true, statistics_fixtures: false } },
      },
    ],
  });
  assertEquals([l.ref, l.name, l.country, l.type, l.currentSeason], ["423", "Ligue 1", "Burkina-Faso", "league", 2025]);
  assertEquals(l.seasons, [2024, 2025]);
  assertEquals(l.coverage, { odds: true, lineups: true, statistics: false, injuries: false, standings: true });
});

/** Base factice : chaque table renvoie ses lignes ; les appels sont notés. */
function fakeDb(tables: Record<string, unknown[]>) {
  const calls: { table: string; op: string; args: unknown[] }[] = [];
  const builder = (table: string) => {
    const b: Record<string, unknown> = {};
    for (const op of ["select", "eq", "is", "in", "lt", "gte", "lte", "limit", "order", "like", "update", "insert", "upsert", "single"]) {
      b[op] = (...args: unknown[]) => {
        calls.push({ table, op, args });
        return b;
      };
    }
    b.then = (resolve: (v: unknown) => unknown) => resolve({ data: tables[table] ?? [], error: null });
    return b;
  };
  return { db: { from: builder } as unknown as SupabaseClient, calls };
}

function fakeProvider(catalog: CatalogLeague[] = []): SportsDataProvider & { asked: string[][] } {
  const asked: string[][] = [];
  return {
    id: "api_football",
    requestsUsed: 0,
    requestsRemaining: null,
    asked,
    getLeague: () => Promise.resolve(null),
    getFixtures: () => Promise.resolve([]),
    getFixturesByIds: (refs: string[]) => {
      asked.push(refs);
      return Promise.resolve([]);
    },
    getStandings: () => Promise.resolve([]),
    getOdds: () => Promise.resolve([]),
    getLeagueCatalog: () => Promise.resolve(catalog),
  };
}

Deno.test("matchs des coupons non réglés : plateforme, coupons personnels et carnet", async () => {
  const { db, calls } = fakeDb({
    app_settings: [],
    sync_runs: [],
    coupon_selections: [{ match_id: 1 }, { match_id: 2 }],
    user_coupon_selections: [{ match_id: 2 }, { match_id: 3 }],
    bet_journal: [{ legs: [{ match_id: 4 }, { match_id: "x" }] }],
    matches: [{ provider_ref: "1001" }],
  });
  const sync = new SportsSync(db, fakeProvider());
  await sync.loadSettings();
  const refs = await sync.openCouponMatchRefs();
  assertEquals(refs, ["1001"]);
  const ids = calls.find((c) => c.table === "matches" && c.op === "in" && c.args[0] === "id")?.args[1];
  assertEquals(ids, [1, 2, 3, 4]);
  const statuses = calls.find((c) => c.table === "matches" && c.op === "in" && c.args[0] === "status")?.args[1];
  assertEquals((statuses as string[]).includes("finished"), false);
});

Deno.test("tâche catalog : toutes les compétitions en une requête, enregistrées par lots", async () => {
  const league = (ref: string): CatalogLeague => ({
    ref, name: `L${ref}`, type: "league", country: "X", countryCode: "XX", logoUrl: null, currentSeason: 2025,
    seasons: [2025], coverage: { odds: true, lineups: false, statistics: false, injuries: false, standings: true },
  });
  const { db, calls } = fakeDb({ app_settings: [], sync_runs: [{ id: 1 }] });
  const sync = new SportsSync(db, fakeProvider([league("1"), league("2")]));
  const r = await sync.run("catalog");
  assertEquals(r.status, "success");
  assertEquals(r.items, 2);
  const upsert = calls.find((c) => c.table === "provider_leagues" && c.op === "upsert");
  assertEquals((upsert?.args[0] as { provider_ref: string }[]).map((x) => x.provider_ref), ["1", "2"]);
});
