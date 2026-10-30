// Tâches de synchronisation : écrivent en base avec le rôle service, en respectant un
// budget journalier de requêtes, et tracent chaque passage dans sync_runs.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { summarizeOdds } from "./normalize.ts";
import type { ProviderFixture, ProviderTeam, SportsDataProvider } from "./types.ts";

export type SyncJob = "daily" | "odds" | "live";

export interface SyncSettings {
  dailyBudget: number;
  oddsWindowHours: number;
  oddsMaxFixtures: number;
  liveLookbackHours: number;
  /** Saison passée à charger à la place de la saison en cours (offre gratuite), ou null. */
  archiveSeason: number | null;
  minRequestIntervalMs: number;
}

const DEFAULTS: SyncSettings = {
  dailyBudget: 95,
  oddsWindowHours: 48,
  oddsMaxFixtures: 12,
  liveLookbackHours: 3,
  archiveSeason: null,
  minRequestIntervalMs: 0,
};

export class BudgetExhausted extends Error {
  constructor() {
    super("Budget journalier de requêtes atteint");
    this.name = "BudgetExhausted";
  }
}

interface RunReport {
  status: "success" | "partial" | "failed" | "skipped";
  items: number;
  error?: string;
  details: Record<string, unknown>;
}

export class SportsSync {
  private usedBefore = 0;
  private settings: SyncSettings = DEFAULTS;

  private readonly startedAt = Date.now();

  constructor(
    private readonly db: SupabaseClient,
    private readonly provider: SportsDataProvider,
    /** Durée maximale d'un passage (les fonctions serveur sont limitées en temps). */
    private readonly timeBudgetMs = 100_000,
  ) {}

  private outOfTime(): boolean {
    return Date.now() - this.startedAt > this.timeBudgetMs;
  }

  async loadSettings(): Promise<void> {
    const { data, error } = await this.db.from("app_settings").select("key, value").like("key", "sports.%");
    if (error) throw new Error(`Réglages illisibles : ${error.message}`);
    const map = new Map<string, unknown>((data ?? []).map((r: { key: string; value: unknown }) => [r.key, r.value] as [string, unknown]));
    const n = (key: string, d: number) => {
      const v = Number(map.get(key));
      return Number.isFinite(v) && v >= 0 ? v : d;
    };
    this.settings = {
      dailyBudget: n("sports.daily_request_budget", DEFAULTS.dailyBudget),
      oddsWindowHours: n("sports.odds_window_hours", DEFAULTS.oddsWindowHours),
      oddsMaxFixtures: n("sports.odds_max_fixtures_per_run", DEFAULTS.oddsMaxFixtures),
      liveLookbackHours: n("sports.live_lookback_hours", DEFAULTS.liveLookbackHours),
      archiveSeason: Number.isInteger(Number(map.get("sports.archive_season"))) && map.get("sports.archive_season") !== null
        ? Number(map.get("sports.archive_season"))
        : null,
      minRequestIntervalMs: n("sports.min_request_interval_ms", DEFAULTS.minRequestIntervalMs),
    };
    this.provider.configure?.({ minIntervalMs: this.settings.minRequestIntervalMs });
    const since = new Date();
    since.setUTCHours(0, 0, 0, 0);
    const runs = await this.db.from("sync_runs").select("requests_used").gte("started_at", since.toISOString());
    if (runs.error) throw new Error(`Journal illisible : ${runs.error.message}`);
    this.usedBefore = (runs.data ?? []).reduce((s: number, r: { requests_used: number }) => s + (r.requests_used ?? 0), 0);
  }

  /** Lève BudgetExhausted si la prochaine requête dépasserait le budget ou le quota du fournisseur. */
  private guard(cost = 1): void {
    const used = this.usedBefore + this.provider.requestsUsed;
    if (used + cost > this.settings.dailyBudget) throw new BudgetExhausted();
    const remaining = this.provider.requestsRemaining;
    if (remaining !== null && remaining < cost + 1) throw new BudgetExhausted();
  }

  async run(job: SyncJob): Promise<Record<string, unknown>> {
    await this.loadSettings();

    // Le suivi en direct ne journalise rien quand il n'y a aucun match à suivre.
    if (job === "live") {
      const refs = await this.liveCandidates();
      if (refs.length === 0) return { job, status: "skipped", reason: "aucun match en cours" };
    }

    const { data: runRow, error: runError } = await this.db
      .from("sync_runs")
      .insert({ provider_id: this.provider.id, job, status: "running" })
      .select("id")
      .single();
    if (runError) throw new Error(`Journal non écrit : ${runError.message}`);

    let report: RunReport;
    try {
      report = job === "daily" ? await this.daily() : job === "odds" ? await this.odds() : await this.live();
    } catch (e) {
      report = {
        status: "failed",
        items: 0,
        error: e instanceof Error ? e.message : String(e),
        details: {},
      };
    }

    await this.db.from("sync_runs").update({
      status: report.status,
      finished_at: new Date().toISOString(),
      requests_used: this.provider.requestsUsed,
      requests_remaining: this.provider.requestsRemaining,
      items_upserted: report.items,
      error: report.error ?? null,
      details: report.details,
    }).eq("id", runRow.id);

    return { job, runId: runRow.id, ...report, requestsUsed: this.provider.requestsUsed };
  }

  // ---------------------------------------------------------------------------
  // Tâche quotidienne : saison en cours, calendrier complet + résultats, classement
  // ---------------------------------------------------------------------------
  private async daily(): Promise<RunReport> {
    const { data: comps, error } = await this.db
      .from("competitions")
      .select("id, provider_ref, name")
      .eq("provider_id", this.provider.id)
      .eq("is_active", true)
      .order("priority");
    if (error) throw new Error(error.message);

    let items = 0;
    const problems: string[] = [];
    const done: string[] = [];
    try {
      const archive = this.settings.archiveSeason;
      for (const c of comps ?? []) {
        if (this.outOfTime()) {
          problems.push("durée maximale atteinte : compétitions restantes au prochain passage");
          break;
        }
        try {
          // Une saison d'archive est terminée : une fois chargée, inutile de la redemander.
          if (archive !== null) {
            const existing = await this.db
              .from("matches")
              .select("id", { count: "exact", head: true })
              .eq("competition_id", c.id)
              .eq("season", archive);
            if ((existing.count ?? 0) > 0) {
              done.push(`${c.name} (archive ${archive} déjà chargée)`);
              continue;
            }
          }
          this.guard(2);
          const league = await this.provider.getLeague(c.provider_ref);
          if (!league) {
            problems.push(`${c.name} (${c.provider_ref}) : inconnue chez le fournisseur`);
            continue;
          }
          await this.db.from("competitions").update({
            name: league.name,
            country: league.country,
            country_code: league.countryCode,
            logo_url: league.logoUrl,
            type: league.type,
            current_season: archive ?? league.currentSeason,
            verified_at: new Date().toISOString(),
          }).eq("id", c.id);
          const season = archive ?? league.currentSeason;
          if (!season) {
            problems.push(`${league.name} : pas de saison en cours`);
            continue;
          }

          this.guard();
          const fixtures = await this.provider.getFixtures(c.provider_ref, season);
          items += await this.saveFixtures(c.id, fixtures);

          this.guard();
          const table = await this.provider.getStandings(c.provider_ref, season);
          items += await this.saveStandings(c.id, season, table);
          done.push(league.name);
        } catch (e) {
          if (e instanceof BudgetExhausted) throw e;
          problems.push(`${c.name} : ${e instanceof Error ? e.message : e}`);
        }
      }
    } catch (e) {
      if (!(e instanceof BudgetExhausted)) throw e;
      problems.push("budget journalier atteint : compétitions restantes reportées");
    }
    return {
      status: problems.length === 0 ? "success" : done.length > 0 ? "partial" : "failed",
      items,
      error: problems.length > 0 ? problems.join(" | ").slice(0, 2000) : undefined,
      details: { competitions: done, problems },
    };
  }

  // ---------------------------------------------------------------------------
  // Cotes des prochains matchs (médiane + meilleure cote par issue)
  // ---------------------------------------------------------------------------
  private async odds(): Promise<RunReport> {
    const now = new Date();
    const until = new Date(now.getTime() + this.settings.oddsWindowHours * 3600_000);
    const { data: matches, error } = await this.db
      .from("matches")
      .select("id, provider_ref, competitions!inner(is_active)")
      .eq("provider_id", this.provider.id)
      .eq("status", "scheduled")
      .eq("competitions.is_active", true)
      .gte("kickoff_at", now.toISOString())
      .lte("kickoff_at", until.toISOString())
      .order("kickoff_at")
      .limit(this.settings.oddsMaxFixtures * 3);
    if (error) throw new Error(error.message);

    // On ne relève pas une cote mise à jour il y a moins de 3 heures.
    const ids = (matches ?? []).map((m: { id: number }) => m.id);
    const recent = new Set<number>();
    if (ids.length > 0) {
      const since = new Date(now.getTime() - 3 * 3600_000).toISOString();
      const r = await this.db.from("odds_snapshots").select("match_id").in("match_id", ids).gte("captured_at", since);
      for (const row of r.data ?? []) recent.add(row.match_id);
    }
    const todo = (matches ?? []).filter((m: { id: number }) => !recent.has(m.id)).slice(0, this.settings.oddsMaxFixtures);

    let items = 0;
    let withoutOdds = 0;
    let budgetHit = false;
    for (const m of todo) {
      if (this.outOfTime()) {
        budgetHit = true;
        break;
      }
      try {
        this.guard();
      } catch {
        budgetHit = true;
        break;
      }
      const summary = summarizeOdds(await this.provider.getOdds(m.provider_ref));
      if (summary.length === 0) {
        withoutOdds++;
        continue;
      }
      const capturedAt = new Date().toISOString();
      const { error: insErr } = await this.db.from("odds_snapshots").insert(
        summary.map((s) => ({
          match_id: m.id,
          market_code: s.market,
          outcome_code: s.outcome,
          line: s.line,
          odd_median: s.median,
          odd_best: s.best,
          bookmakers_count: s.count,
          captured_at: capturedAt,
        })),
      );
      if (insErr) throw new Error(insErr.message);
      items += summary.length;
    }
    return {
      status: budgetHit ? "partial" : "success",
      items,
      error: budgetHit ? "budget journalier atteint" : undefined,
      details: { candidates: todo.length, withoutOdds },
    };
  }

  // ---------------------------------------------------------------------------
  // Scores en direct des matchs commencés et non terminés
  // ---------------------------------------------------------------------------
  private async liveCandidates(): Promise<string[]> {
    const now = new Date();
    const from = new Date(now.getTime() - this.settings.liveLookbackHours * 3600_000).toISOString();
    const { data, error } = await this.db
      .from("matches")
      .select("provider_ref")
      .eq("provider_id", this.provider.id)
      .in("status", ["scheduled", "live", "interrupted"])
      .gte("kickoff_at", from)
      .lte("kickoff_at", now.toISOString())
      .limit(100);
    if (error) throw new Error(error.message);
    return (data ?? []).map((r: { provider_ref: string }) => r.provider_ref);
  }

  private async live(): Promise<RunReport> {
    const refs = await this.liveCandidates();
    this.guard(Math.ceil(refs.length / 20));
    const fixtures = await this.provider.getFixturesByIds(refs);
    const { data: comps } = await this.db.from("competitions").select("id, provider_ref").eq("provider_id", this.provider.id);
    const compByRef = new Map((comps ?? []).map((c: { id: number; provider_ref: string }) => [c.provider_ref, c.id] as [string, number]));
    let items = 0;
    for (const [leagueRef, list] of groupBy(fixtures, (f) => f.leagueRef)) {
      const compId = compByRef.get(leagueRef);
      if (compId !== undefined) items += await this.saveFixtures(compId, list);
    }
    return { status: "success", items, details: { tracked: refs.length } };
  }

  // ---------------------------------------------------------------------------
  // Écritures
  // ---------------------------------------------------------------------------
  private async saveTeams(teams: ProviderTeam[]): Promise<Map<string, number>> {
    const unique = [...new Map(teams.map((t) => [t.ref, t] as [string, ProviderTeam])).values()];
    const ids = new Map<string, number>();
    for (const chunk of chunks(unique, 500)) {
      const { data, error } = await this.db
        .from("teams")
        .upsert(
          chunk.map((t) => ({ provider_id: this.provider.id, provider_ref: t.ref, name: t.name, logo_url: t.logoUrl })),
          { onConflict: "provider_id,provider_ref" },
        )
        .select("id, provider_ref");
      if (error) throw new Error(`Équipes : ${error.message}`);
      for (const row of data ?? []) ids.set(row.provider_ref, row.id);
    }
    return ids;
  }

  private async saveFixtures(competitionId: number, fixtures: ProviderFixture[]): Promise<number> {
    if (fixtures.length === 0) return 0;
    const teamIds = await this.saveTeams(fixtures.flatMap((f) => [f.home, f.away]));
    const now = new Date().toISOString();
    const rows = fixtures
      .filter((f) => teamIds.has(f.home.ref) && teamIds.has(f.away.ref) && f.home.ref !== f.away.ref)
      .map((f) => ({
        provider_id: this.provider.id,
        provider_ref: f.ref,
        competition_id: competitionId,
        season: f.season,
        round: f.round,
        kickoff_at: f.kickoffAt,
        status: f.status,
        status_short: f.statusShort,
        elapsed: f.elapsed,
        home_team_id: teamIds.get(f.home.ref),
        away_team_id: teamIds.get(f.away.ref),
        home_goals: f.homeGoals,
        away_goals: f.awayGoals,
        ht_home_goals: f.htHomeGoals,
        ht_away_goals: f.htAwayGoals,
        venue: f.venue,
        referee: f.referee,
        source_updated_at: now,
      }));
    for (const chunk of chunks(rows, 500)) {
      const { error } = await this.db.from("matches").upsert(chunk, { onConflict: "provider_id,provider_ref" });
      if (error) throw new Error(`Matchs : ${error.message}`);
    }
    return rows.length;
  }

  private async saveStandings(
    competitionId: number,
    season: number,
    table: Awaited<ReturnType<SportsDataProvider["getStandings"]>>,
  ): Promise<number> {
    if (table.length === 0) return 0;
    const teamIds = await this.saveTeams(table.map((s) => s.team));
    const rows = table
      .filter((s) => teamIds.has(s.team.ref))
      .map((s) => ({
        competition_id: competitionId,
        season,
        group_name: s.group,
        team_id: teamIds.get(s.team.ref),
        rank: s.rank,
        points: s.points,
        played: s.played,
        win: s.win,
        draw: s.draw,
        lose: s.lose,
        goals_for: s.goalsFor,
        goals_against: s.goalsAgainst,
        goal_diff: s.goalDiff,
        form: s.form,
        description: s.description,
        home: s.home,
        away: s.away,
        updated_at: new Date().toISOString(),
      }));
    // Le classement est remplacé en entier : les équipes reléguées ou changées de groupe disparaissent.
    const del = await this.db.from("standings").delete().eq("competition_id", competitionId).eq("season", season);
    if (del.error) throw new Error(`Classement : ${del.error.message}`);
    const ins = await this.db.from("standings").insert(rows);
    if (ins.error) throw new Error(`Classement : ${ins.error.message}`);
    return rows.length;
  }
}

function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

function groupBy<T>(items: T[], key: (item: T) => string): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const item of items) {
    const k = key(item);
    const list = map.get(k);
    if (list) list.push(item);
    else map.set(k, [item]);
  }
  return map;
}
