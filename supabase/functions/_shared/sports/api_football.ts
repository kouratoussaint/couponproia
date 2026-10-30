// Adaptateur API-Football (https://v3.football.api-sports.io).
import { normalizeBet, normalizeStatus } from "./normalize.ts";
import type {
  OddsQuote,
  ProviderFixture,
  ProviderLeague,
  ProviderStanding,
  ProviderTeam,
  SportsDataProvider,
} from "./types.ts";

// Les réponses du fournisseur ne sont pas typées : on les lit défensivement.
// deno-lint-ignore no-explicit-any
type Json = any;

export class ApiFootballError extends Error {
  constructor(message: string, readonly kind: "http" | "api" | "network") {
    super(message);
    this.name = "ApiFootballError";
  }
}

const BASE_URL = "https://v3.football.api-sports.io";

const num = (v: unknown, fallback = 0): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};
const numOrNull = (v: unknown): number | null =>
  v === null || v === undefined || v === "" || !Number.isFinite(Number(v)) ? null : Number(v);
const strOrNull = (v: unknown): string | null =>
  typeof v === "string" && v.trim() !== "" ? v : null;

function team(t: Json): ProviderTeam {
  return { ref: String(t?.id), name: String(t?.name ?? "?"), logoUrl: strOrNull(t?.logo) };
}

export function parseFixture(r: Json): ProviderFixture {
  return {
    ref: String(r.fixture.id),
    leagueRef: String(r.league?.id),
    season: num(r.league?.season),
    round: strOrNull(r.league?.round),
    kickoffAt: String(r.fixture.date),
    status: normalizeStatus(r.fixture.status?.short),
    statusShort: String(r.fixture.status?.short ?? ""),
    elapsed: numOrNull(r.fixture.status?.elapsed),
    home: team(r.teams?.home),
    away: team(r.teams?.away),
    homeGoals: numOrNull(r.goals?.home),
    awayGoals: numOrNull(r.goals?.away),
    htHomeGoals: numOrNull(r.score?.halftime?.home),
    htAwayGoals: numOrNull(r.score?.halftime?.away),
    venue: strOrNull(r.fixture.venue?.name),
    referee: strOrNull(r.fixture.referee),
  };
}

export function parseLeague(r: Json): ProviderLeague {
  const seasons: Json[] = Array.isArray(r?.seasons) ? r.seasons : [];
  const current = seasons.find((s) => s?.current === true);
  const type = String(r?.league?.type ?? "").toLowerCase();
  return {
    ref: String(r?.league?.id),
    name: String(r?.league?.name ?? "?"),
    type: type === "league" ? "league" : type === "cup" ? "cup" : null,
    country: strOrNull(r?.country?.name),
    countryCode: strOrNull(r?.country?.code),
    logoUrl: strOrNull(r?.league?.logo),
    currentSeason: current ? numOrNull(current.year) : null,
  };
}

export function parseStandings(r: Json): ProviderStanding[] {
  const groups: Json[] = Array.isArray(r?.league?.standings) ? r.league.standings : [];
  const rows: ProviderStanding[] = [];
  for (const group of groups) {
    if (!Array.isArray(group)) continue;
    for (const s of group) {
      rows.push({
        team: team(s.team),
        group: String(s.group ?? ""),
        rank: num(s.rank),
        points: num(s.points),
        played: num(s.all?.played),
        win: num(s.all?.win),
        draw: num(s.all?.draw),
        lose: num(s.all?.lose),
        goalsFor: num(s.all?.goals?.for),
        goalsAgainst: num(s.all?.goals?.against),
        goalDiff: num(s.goalsDiff),
        form: strOrNull(s.form),
        description: strOrNull(s.description),
        home: s.home ?? null,
        away: s.away ?? null,
      });
    }
  }
  return rows;
}

export function parseOdds(r: Json): OddsQuote[] {
  const quotes: OddsQuote[] = [];
  const books: Json[] = Array.isArray(r?.bookmakers) ? r.bookmakers : [];
  for (const b of books) {
    const bookmaker = String(b?.name ?? b?.id ?? "?");
    for (const bet of Array.isArray(b?.bets) ? b.bets : []) {
      for (const v of Array.isArray(bet?.values) ? bet.values : []) {
        const normalized = normalizeBet(String(bet?.name ?? ""), String(v?.value ?? ""));
        if (!normalized) continue;
        quotes.push({ bookmaker, ...normalized, odd: Number(v?.odd) });
      }
    }
  }
  return quotes;
}

export class ApiFootballProvider implements SportsDataProvider {
  readonly id = "api_football";
  requestsUsed = 0;
  requestsRemaining: number | null = null;
  private minIntervalMs = 0;
  private lastRequestAt = 0;

  constructor(
    private readonly apiKey: string,
    private readonly fetchFn: typeof fetch = fetch,
    private readonly sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
    private readonly retryAfterMs = 7000,
  ) {}

  configure(options: { minIntervalMs: number }): void {
    this.minIntervalMs = Math.max(0, options.minIntervalMs);
  }

  private async send(url: URL, path: string): Promise<Response> {
    const wait = this.lastRequestAt + this.minIntervalMs - Date.now();
    if (wait > 0) await this.sleep(wait);
    this.lastRequestAt = Date.now();
    try {
      return await this.fetchFn(url, { headers: { "x-apisports-key": this.apiKey } });
    } catch (e) {
      throw new ApiFootballError(`Réseau indisponible (${path}) : ${e instanceof Error ? e.message : e}`, "network");
    }
  }

  private async get(path: string, params: Record<string, string | number>): Promise<Json[]> {
    const url = new URL(BASE_URL + path);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
    let res = await this.send(url, path);
    this.requestsUsed++;
    if (res.status === 429) {
      // Limite par minute atteinte : on patiente puis on réessaie une fois.
      await res.body?.cancel();
      await this.sleep(this.retryAfterMs);
      res = await this.send(url, path);
      this.requestsUsed++;
    }
    const remaining = res.headers.get("x-ratelimit-requests-remaining");
    if (remaining !== null && remaining !== "" && Number.isFinite(Number(remaining))) {
      this.requestsRemaining = Number(remaining);
    }
    if (!res.ok) {
      throw new ApiFootballError(`HTTP ${res.status} sur ${path}`, "http");
    }
    const body: Json = await res.json();
    const errors = body?.errors;
    const hasErrors = Array.isArray(errors) ? errors.length > 0 : errors && Object.keys(errors).length > 0;
    if (hasErrors) {
      throw new ApiFootballError(`${path} : ${JSON.stringify(errors)}`, "api");
    }
    return Array.isArray(body?.response) ? body.response : [];
  }

  async getLeague(ref: string): Promise<ProviderLeague | null> {
    const rows = await this.get("/leagues", { id: ref, current: "true" });
    if (rows.length > 0) return parseLeague(rows[0]);
    // Compétition hors saison : on récupère quand même ses informations.
    const all = await this.get("/leagues", { id: ref });
    return all.length > 0 ? parseLeague(all[0]) : null;
  }

  async getFixtures(leagueRef: string, season: number): Promise<ProviderFixture[]> {
    const rows = await this.get("/fixtures", { league: leagueRef, season });
    return rows.map(parseFixture);
  }

  async getFixturesByIds(refs: string[]): Promise<ProviderFixture[]> {
    const out: ProviderFixture[] = [];
    for (let i = 0; i < refs.length; i += 20) {
      const rows = await this.get("/fixtures", { ids: refs.slice(i, i + 20).join("-") });
      out.push(...rows.map(parseFixture));
    }
    return out;
  }

  async getStandings(leagueRef: string, season: number): Promise<ProviderStanding[]> {
    const rows = await this.get("/standings", { league: leagueRef, season });
    return rows.length > 0 ? parseStandings(rows[0]) : [];
  }

  async getOdds(fixtureRef: string): Promise<OddsQuote[]> {
    const rows = await this.get("/odds", { fixture: fixtureRef });
    return rows.length > 0 ? parseOdds(rows[0]) : [];
  }
}
