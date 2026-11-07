// Tâches de synchronisation : écrivent en base avec le rôle service, en respectant un
// budget journalier de requêtes, et tracent chaque passage dans sync_runs.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { summarizeOdds } from "./normalize.ts";
import type { ProviderAbsence, ProviderFixture, ProviderTeam, SportsDataProvider } from "./types.ts";

export type SyncJob = "daily" | "odds" | "live" | "matchday" | "catalog";

/** Statuts encore à suivre (un match dans cet état peut encore changer de score ou de date). */
const OPEN_STATUSES = ["scheduled", "live", "interrupted", "postponed", "unknown"];

export interface SyncSettings {
  dailyBudget: number;
  oddsWindowHours: number;
  oddsMaxFixtures: number;
  liveLookbackHours: number;
  /** Saison passée à charger à la place de la saison en cours (offre gratuite), ou null. */
  archiveSeason: number | null;
  minRequestIntervalMs: number;
  /** Saisons passées à charger une fois (calendrier et résultats), pour l'historique du moteur. */
  historySeasons: number[];
}

const DEFAULTS: SyncSettings = {
  dailyBudget: 95,
  oddsWindowHours: 48,
  oddsMaxFixtures: 12,
  liveLookbackHours: 3,
  archiveSeason: null,
  minRequestIntervalMs: 0,
  historySeasons: [],
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
      historySeasons: Array.isArray(map.get("sports.history_seasons"))
        ? (map.get("sports.history_seasons") as unknown[]).map(Number).filter((x) => Number.isInteger(x) && x > 1990)
        : [],
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

  async run(job: SyncJob, options: { competitionId?: number } = {}): Promise<Record<string, unknown>> {
    await this.loadSettings();

    // Le suivi en direct et le jour de match ne journalisent rien quand il n'y a rien à faire.
    if (job === "live") {
      const refs = await this.liveCandidates();
      if (refs.length === 0) return { job, status: "skipped", reason: "aucun match en cours" };
    }
    if (job === "matchday") {
      const todo = await this.matchdayCandidates();
      if (todo.lineups.length === 0 && todo.absences.length === 0) {
        return { job, status: "skipped", reason: "rien à vérifier" };
      }
    }

    const { data: runRow, error: runError } = await this.db
      .from("sync_runs")
      .insert({ provider_id: this.provider.id, job, status: "running" })
      .select("id")
      .single();
    if (runError) throw new Error(`Journal non écrit : ${runError.message}`);

    let report: RunReport;
    try {
      report = job === "daily"
        ? await this.daily(options.competitionId)
        : job === "catalog"
        ? await this.catalog()
        : job === "odds"
        ? await this.odds()
        : job === "matchday"
        ? await this.matchday()
        : await this.live();
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
  private async daily(competitionId?: number): Promise<RunReport> {
    let query = this.db
      .from("competitions")
      .select("id, provider_ref, name")
      .eq("provider_id", this.provider.id)
      .eq("is_active", true);
    // Compétition qu'on vient d'ajouter : chargée seule, tout de suite.
    if (competitionId !== undefined) query = query.eq("id", competitionId);
    const { data: comps, error } = await query.order("priority");
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

          // Historique : saisons passées terminées, chargées une seule fois (1 requête chacune).
          for (const past of this.settings.historySeasons) {
            if (past === season || this.outOfTime()) continue;
            const existing = await this.db.from("matches").select("id", { count: "exact", head: true })
              .eq("competition_id", c.id).eq("season", past);
            if ((existing.count ?? 0) > 0) continue;
            this.guard();
            const pastFixtures = await this.provider.getFixtures(c.provider_ref, past);
            items += await this.saveFixtures(c.id, pastFixtures);
            done.push(`${league.name} ${past} (historique)`);
          }
        } catch (e) {
          if (e instanceof BudgetExhausted) throw e;
          problems.push(`${c.name} : ${e instanceof Error ? e.message : e}`);
        }
      }
    } catch (e) {
      if (!(e instanceof BudgetExhausted)) throw e;
      problems.push("budget journalier atteint : compétitions restantes reportées");
    }
    // Matchs des coupons non réglés restés ouverts au-delà du suivi en direct (compétition
    // désactivée, match reporté ou statut jamais finalisé) : rafraîchis un par un.
    let openCoupons = 0;
    if (competitionId === undefined) {
      try {
        openCoupons = await this.refreshOpenCouponMatches();
        items += openCoupons;
      } catch (e) {
        if (e instanceof BudgetExhausted) problems.push("budget journalier atteint : matchs des coupons reportés");
        else problems.push(`Matchs des coupons : ${e instanceof Error ? e.message : e}`);
      }
    }
    return {
      status: problems.length === 0 ? "success" : done.length > 0 ? "partial" : "failed",
      items,
      error: problems.length > 0 ? problems.join(" | ").slice(0, 2000) : undefined,
      details: { competitions: done, problems, open_coupon_matches: openCoupons, ...(competitionId ? { competition_id: competitionId } : {}) },
    };
  }

  /** Matchs présents dans un coupon ou un pari non réglé, non terminés, commencés avant le suivi en direct. */
  async openCouponMatchRefs(): Promise<string[]> {
    const before = new Date(Date.now() - this.settings.liveLookbackHours * 3600_000).toISOString();
    const ids = new Set<number>();
    const platform = await this.db.from("coupon_selections").select("match_id, coupon:coupons!inner(result, status)")
      .is("coupon.result", null).eq("coupon.status", "published").limit(5000);
    if (platform.error) throw new Error(platform.error.message);
    for (const r of platform.data ?? []) ids.add(r.match_id);
    const mine = await this.db.from("user_coupon_selections").select("match_id, coupon:user_coupons!inner(result)")
      .is("coupon.result", null).limit(5000);
    if (mine.error) throw new Error(mine.error.message);
    for (const r of mine.data ?? []) ids.add(r.match_id);
    const bets = await this.db.from("bet_journal").select("legs").is("result", null).limit(5000);
    if (bets.error) throw new Error(bets.error.message);
    for (const b of bets.data ?? []) {
      for (const l of (Array.isArray(b.legs) ? b.legs : []) as { match_id?: unknown }[]) {
        const id = Number(l?.match_id);
        if (Number.isInteger(id)) ids.add(id);
      }
    }
    if (ids.size === 0) return [];
    const refs: string[] = [];
    for (const chunk of chunks([...ids], 200)) {
      const { data, error } = await this.db.from("matches").select("provider_ref")
        .eq("provider_id", this.provider.id).in("id", chunk).in("status", OPEN_STATUSES).lt("kickoff_at", before);
      if (error) throw new Error(error.message);
      refs.push(...(data ?? []).map((m: { provider_ref: string }) => m.provider_ref));
    }
    return refs;
  }

  private async refreshOpenCouponMatches(): Promise<number> {
    const refs = await this.openCouponMatchRefs();
    if (refs.length === 0) return 0;
    this.guard(Math.ceil(refs.length / 20));
    const fixtures = await this.provider.getFixturesByIds(refs);
    return await this.saveFixturesByLeague(fixtures);
  }

  /** Enregistre des matchs de compétitions diverses (toutes compétitions connues, quel que soit leur état). */
  private async saveFixturesByLeague(fixtures: ProviderFixture[]): Promise<number> {
    const { data: comps } = await this.db.from("competitions").select("id, provider_ref").eq("provider_id", this.provider.id);
    const compByRef = new Map((comps ?? []).map((c: { id: number; provider_ref: string }) => [c.provider_ref, c.id] as [string, number]));
    let items = 0;
    for (const [leagueRef, list] of groupBy(fixtures, (f) => f.leagueRef)) {
      const compId = compByRef.get(leagueRef);
      if (compId !== undefined) items += await this.saveFixtures(compId, list);
    }
    return items;
  }

  // ---------------------------------------------------------------------------
  // Catalogue du fournisseur (hebdomadaire) : toutes les compétitions, 1 requête
  // ---------------------------------------------------------------------------
  private async catalog(): Promise<RunReport> {
    if (!this.provider.getLeagueCatalog) {
      return { status: "skipped", items: 0, error: "catalogue non proposé par ce fournisseur", details: {} };
    }
    this.guard();
    const leagues = await this.provider.getLeagueCatalog();
    const now = new Date().toISOString();
    let items = 0;
    for (const chunk of chunks(leagues.filter((l) => l.ref && l.ref !== "undefined"), 500)) {
      const { error } = await this.db.from("provider_leagues").upsert(
        chunk.map((l) => ({
          provider_id: this.provider.id,
          provider_ref: l.ref,
          name: l.name,
          type: l.type,
          country: l.country,
          country_code: l.countryCode,
          logo_url: l.logoUrl,
          current_season: l.currentSeason,
          seasons: l.seasons,
          coverage: l.coverage,
          refreshed_at: now,
        })),
        { onConflict: "provider_id,provider_ref" },
      );
      if (error) throw new Error(`Catalogue : ${error.message}`);
      items += chunk.length;
    }
    return { status: "success", items, details: { leagues: items } };
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
    const items = await this.saveFixturesByLeague(fixtures);
    const lineups = await this.saveLineups(fixtures);
    return { status: "success", items, details: { tracked: refs.length, lineups } };
  }

  // ---------------------------------------------------------------------------
  // Jour de match : compositions (dès leur publication) et absents annoncés
  // ---------------------------------------------------------------------------
  private async matchdayCandidates(): Promise<{ lineups: string[]; absences: { id: number; ref: string }[] }> {
    const now = Date.now();
    const iso = (ms: number) => new Date(ms).toISOString();
    const { data: soon, error } = await this.db
      .from("matches")
      .select("id, provider_ref, kickoff_at, absences_checked_at, competition:competitions!inner(is_active), lineups:match_lineups(team_id)")
      .eq("provider_id", this.provider.id)
      .eq("status", "scheduled")
      .eq("competition.is_active", true)
      .gte("kickoff_at", iso(now - 15 * 60_000))
      .lte("kickoff_at", iso(now + 6 * 3600_000))
      .limit(300);
    if (error) throw new Error(error.message);
    type Row = { id: number; provider_ref: string; kickoff_at: string; absences_checked_at: string | null; lineups: unknown[] };
    const rows = (soon ?? []) as unknown as Row[];
    const lineups = rows
      .filter((r) => Date.parse(r.kickoff_at) <= now + 75 * 60_000 && (r.lineups?.length ?? 0) < 2)
      .map((r) => r.provider_ref);
    const absences = this.provider.getAbsences
      ? rows
        .filter((r) => !r.absences_checked_at || Date.parse(r.absences_checked_at) < now - 3 * 3600_000)
        .map((r) => ({ id: r.id, ref: r.provider_ref }))
      : [];
    return { lineups, absences };
  }

  private async matchday(): Promise<RunReport> {
    const todo = await this.matchdayCandidates();
    let lineups = 0;
    let absences = 0;
    let budgetHit = false;
    try {
      if (todo.lineups.length) {
        this.guard(Math.ceil(todo.lineups.length / 20));
        lineups = await this.saveLineups(await this.provider.getFixturesByIds(todo.lineups));
      }
      if (todo.absences.length && this.provider.getAbsences) {
        this.guard(Math.ceil(todo.absences.length / 20));
        const found = await this.provider.getAbsences(todo.absences.map((a) => a.ref));
        absences = await this.saveAbsences(todo.absences, found);
      }
    } catch (e) {
      if (!(e instanceof BudgetExhausted)) throw e;
      budgetHit = true;
    }
    return {
      status: budgetHit ? "partial" : "success",
      items: lineups + absences,
      error: budgetHit ? "budget journalier atteint" : undefined,
      details: { lineup_candidates: todo.lineups.length, lineups, absence_matches: todo.absences.length, absences },
    };
  }

  /** Enregistre les compositions publiées (une ligne par équipe et par match). */
  private async saveLineups(fixtures: ProviderFixture[]): Promise<number> {
    const withLineups = fixtures.filter((f) => (f.lineups?.length ?? 0) > 0);
    if (!withLineups.length) return 0;
    const { data: matches } = await this.db.from("matches").select("id, provider_ref")
      .eq("provider_id", this.provider.id).in("provider_ref", withLineups.map((f) => f.ref));
    const matchId = new Map((matches ?? []).map((m: { id: number; provider_ref: string }) => [m.provider_ref, m.id] as [string, number]));
    const teamIds = await this.saveTeams(withLineups.flatMap((f) => f.lineups!.map((l) => l.team)));
    const now = new Date().toISOString();
    const rows = withLineups.flatMap((f) =>
      f.lineups!
        .filter((l) => matchId.has(f.ref) && teamIds.has(l.team.ref))
        .map((l) => ({
          match_id: matchId.get(f.ref),
          team_id: teamIds.get(l.team.ref),
          formation: l.formation,
          coach: l.coach,
          start_xi: l.startXI,
          substitutes: l.substitutes,
          fetched_at: now,
        }))
    );
    if (!rows.length) return 0;
    const { error } = await this.db.from("match_lineups").upsert(rows, { onConflict: "match_id,team_id" });
    if (error) throw new Error(`Compositions : ${error.message}`);
    return rows.length;
  }

  /** Remplace la liste des absents des matchs vérifiés (une liste vide est aussi une information). */
  private async saveAbsences(checked: { id: number; ref: string }[], found: ProviderAbsence[]): Promise<number> {
    const idByRef = new Map(checked.map((c) => [c.ref, c.id] as [string, number]));
    const teamIds = await this.saveTeams(found.map((a) => a.team));
    const now = new Date().toISOString();
    const rows = found
      .filter((a) => idByRef.has(a.fixtureRef) && teamIds.has(a.team.ref))
      .map((a) => ({
        match_id: idByRef.get(a.fixtureRef),
        team_id: teamIds.get(a.team.ref),
        player_name: a.player,
        absence_type: a.type,
        reason: a.reason,
        fetched_at: now,
      }));
    const ids = checked.map((c) => c.id);
    const { error: delError } = await this.db.from("match_absences").delete().in("match_id", ids);
    if (delError) throw new Error(`Absents : ${delError.message}`);
    for (const chunk of chunks(rows, 500)) {
      const { error } = await this.db.from("match_absences").insert(chunk);
      if (error) throw new Error(`Absents : ${error.message}`);
    }
    const { error: upError } = await this.db.from("matches").update({ absences_checked_at: now }).in("id", ids);
    if (upError) throw new Error(`Absents : ${upError.message}`);
    return rows.length;
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
        ft_home_goals: f.ftHomeGoals,
        ft_away_goals: f.ftAwayGoals,
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
