// Accès aux données du moteur de coupons : matchs à venir cotés, fiches calculées en
// lot (sans IA, sans appel au fournisseur), état réel des sélections pour le contrôle.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { buildFiche, type NamedMatch, type OddsRow } from "../engine/fiche.ts";
import type { EngineQuality } from "../engine/quality.ts";
import { outcomeKey, PRIOR_SEASON_WEIGHT, weighted } from "../engine/poisson.ts";
import { type Candidate, justificationFor, type LiveCheck, type Reliability } from "./generator.ts";

const PAGE = 1000;
const PLAYED = ["finished", "awarded"];

interface UpcomingRow {
  id: number;
  season: number;
  round: string | null;
  kickoff_at: string;
  competition: { id: number; name: string; type: string | null } | null;
  home: { id: number; name: string } | null;
  away: { id: number; name: string } | null;
}

interface PlayedRow {
  id: number;
  competition_id: number;
  season: number;
  kickoff_at: string;
  home_team_id: number;
  away_team_id: number;
  home_goals: number;
  away_goals: number;
  home: { name: string } | null;
  away: { name: string } | null;
  competition: { name: string } | null;
}

type Played = NamedMatch & { id: number; competitionId: number; season: number };

function chunks<T>(xs: T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += n) out.push(xs.slice(i, i + n));
  return out;
}

async function paged<T>(query: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>) {
  const rows: T[] = [];
  for (let from = 0;; from += PAGE) {
    const { data, error } = await query(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...(data ?? []));
    if (!data || data.length < PAGE) break;
  }
  return rows;
}

async function latestOdds(db: SupabaseClient, matchIds: number[]): Promise<Map<number, OddsRow[]>> {
  const byMatch = new Map<number, OddsRow[]>();
  for (const ids of chunks(matchIds, 150)) {
    const { data, error } = await db.from("latest_odds")
      .select("match_id, market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at")
      .in("match_id", ids);
    if (error) throw new Error(error.message);
    for (const o of data ?? []) {
      const row: OddsRow = {
        market_code: o.market_code,
        outcome_code: o.outcome_code,
        line: o.line === null ? null : Number(o.line),
        odd_median: Number(o.odd_median),
        odd_best: Number(o.odd_best),
        bookmakers_count: o.bookmakers_count,
        captured_at: o.captured_at,
      };
      byMatch.set(o.match_id, [...(byMatch.get(o.match_id) ?? []), row]);
    }
  }
  return byMatch;
}

export interface CandidateLoad {
  candidates: Candidate[];
  upcomingMatches: number;
  matchesWithOdds: number;
}

/** Candidats de tous les matchs programmés dans la fenêtre et cotés. */
export async function loadCandidates(
  db: SupabaseClient,
  now: Date,
  windowHours: number,
  quality: EngineQuality | null,
  range?: { from: Date; until: Date },
  matchIds?: number[],
): Promise<CandidateLoad> {
  const until = (range?.until ?? new Date(now.getTime() + windowHours * 3600_000)).toISOString();
  const startIso = new Date(Math.max(now.getTime(), range?.from.getTime() ?? 0)).toISOString();
  const upcoming = await paged<UpcomingRow>((from, to) => {
    let q = db.from("matches").select(
      "id, season, round, kickoff_at, competition:competitions(id, name, type), home:teams!matches_home_team_fk(id, name), away:teams!matches_away_team_fk(id, name)",
    ).eq("status", "scheduled").gt("kickoff_at", startIso);
    q = matchIds?.length ? q.in("id", matchIds) : q.lte("kickoff_at", until);
    return q.order("kickoff_at").order("id").range(from, to) as unknown as PromiseLike<{ data: UpcomingRow[] | null; error: { message: string } | null }>;
  });
  const valid = upcoming.filter((m) => m.competition && m.home && m.away);
  const odds = await latestOdds(db, valid.map((m) => m.id));
  const withOdds = valid.filter((m) => (odds.get(m.id) ?? []).length > 0);
  if (withOdds.length === 0) return { candidates: [], upcomingMatches: valid.length, matchesWithOdds: 0 };

  // Matchs joués utiles : saisons des compétitions concernées + derniers matchs des équipes.
  const played = new Map<number, Played>();
  const add = (r: PlayedRow) =>
    played.set(r.id, {
      id: r.id,
      competitionId: r.competition_id,
      season: r.season,
      kickoffAt: r.kickoff_at,
      homeId: r.home_team_id,
      awayId: r.away_team_id,
      homeGoals: r.home_goals,
      awayGoals: r.away_goals,
      homeName: r.home?.name ?? "?",
      awayName: r.away?.name ?? "?",
      competitionName: r.competition?.name,
    });
  const columns =
    "id, competition_id, season, kickoff_at, home_team_id, away_team_id, home_goals, away_goals, home:teams!matches_home_team_fk(name), away:teams!matches_away_team_fk(name), competition:competitions(name)";
  // Saison en cours et précédente de chaque compétition (la précédente sert d'a priori pondéré).
  const pairs = [...new Set(withOdds.flatMap((m) => [`${m.competition!.id}:${m.season}`, `${m.competition!.id}:${m.season - 1}`]))];
  for (const pair of pairs) {
    const [competitionId, season] = pair.split(":").map(Number);
    (await paged<PlayedRow>((from, to) =>
      db.from("matches").select(columns).eq("competition_id", competitionId).eq("season", season)
        .in("status", PLAYED).not("home_goals", "is", null).not("away_goals", "is", null)
        .order("kickoff_at").order("id").range(from, to) as unknown as PromiseLike<{ data: PlayedRow[] | null; error: { message: string } | null }>
    )).forEach(add);
  }
  const teamIds = [...new Set(withOdds.flatMap((m) => [m.home!.id, m.away!.id]))];
  const since = new Date(now.getTime() - 3 * 365 * 24 * 3600_000).toISOString();
  for (const ids of chunks(teamIds, 60)) {
    const list = ids.join(",");
    (await paged<PlayedRow>((from, to) =>
      db.from("matches").select(columns).or(`home_team_id.in.(${list}),away_team_id.in.(${list})`)
        .gte("kickoff_at", since).in("status", PLAYED).not("home_goals", "is", null).not("away_goals", "is", null)
        .order("kickoff_at").order("id").range(from, to) as unknown as PromiseLike<{ data: PlayedRow[] | null; error: { message: string } | null }>
    )).forEach(add);
  }
  const all = [...played.values()].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));

  const candidates: Candidate[] = [];
  for (const m of withOdds) {
    const before = all.filter((p) => p.kickoffAt < m.kickoff_at);
    const homeId = m.home!.id;
    const awayId = m.away!.id;
    const recent = (team: number) =>
      before.filter((p) => p.homeId === team || p.awayId === team).reverse().slice(0, 5);
    const fiche = buildFiche({
      match: {
        id: m.id,
        kickoffAt: m.kickoff_at,
        season: m.season,
        round: m.round,
        competition: m.competition!,
        home: m.home!,
        away: m.away!,
      },
      history: before.filter((p) => p.competitionId === m.competition!.id && p.season === m.season),
      prior: weighted(
        before.filter((p) => p.competitionId === m.competition!.id && p.season === m.season - 1),
        PRIOR_SEASON_WEIGHT,
      ),
      recentHome: recent(homeId),
      recentAway: recent(awayId),
      headToHead: before.filter((p) =>
        (p.homeId === homeId && p.awayId === awayId) || (p.homeId === awayId && p.awayId === homeId)
      ).reverse().slice(0, 5),
      odds: odds.get(m.id) ?? [],
      generatedAt: now.toISOString(),
      quality,
    });
    const rows = odds.get(m.id) ?? [];
    for (const line of fiche.market.lines) {
      if (line.model_probability === null) continue;
      const row = rows.find((o) => outcomeKey(o.market_code, o.outcome_code, o.line) === line.key)!;
      const base = {
        modelProbability: line.model_probability,
        impliedProbability: line.implied_probability,
        edge: line.edge,
        home: m.home!.name,
        away: m.away!.name,
      };
      candidates.push({
        matchId: m.id,
        competitionId: m.competition!.id,
        competitionName: m.competition!.name,
        kickoffAt: m.kickoff_at,
        key: line.key,
        marketCode: row.market_code,
        outcomeCode: row.outcome_code,
        line: row.line,
        odd: line.odd_median,
        oddBest: line.odd_best,
        bookmakers: line.bookmakers,
        oddsCapturedAt: row.captured_at,
        reliability: fiche.reliability as Reliability,
        justification: justificationFor(base, fiche),
        ...base,
      });
    }
  }
  return { candidates, upcomingMatches: valid.length, matchesWithOdds: withOdds.length };
}

/** État réel (relu en base) des sélections : statut, heure, cote actuelle de l'issue. */
export async function loadLiveChecks(db: SupabaseClient, keys: { matchId: number; key: string }[]) {
  const ids = [...new Set(keys.map((k) => k.matchId))];
  const live = new Map<string, LiveCheck>();
  if (ids.length === 0) return live;
  const { data: matches, error } = await db.from("matches").select("id, status, kickoff_at").in("id", ids);
  if (error) throw new Error(error.message);
  const odds = await latestOdds(db, ids);
  for (const k of keys) {
    const m = (matches ?? []).find((x) => x.id === k.matchId);
    const o = (odds.get(k.matchId) ?? []).find((r) => outcomeKey(r.market_code, r.outcome_code, r.line) === k.key);
    live.set(`${k.matchId}:${k.key}`, {
      matchExists: Boolean(m),
      status: m?.status ?? null,
      kickoffAt: m?.kickoff_at ?? null,
      currentOdd: o ? o.odd_median : null,
      oddsCapturedAt: o?.captured_at ?? null,
    });
  }
  return live;
}

/** Empreintes des coupons en circulation (à valider, prêts, publiés). */
export async function liveFingerprints(db: SupabaseClient): Promise<Set<string>> {
  const { data, error } = await db.from("coupons").select("fingerprint")
    .in("status", ["pending_review", "ready", "published"]).gte("last_kickoff_at", new Date(Date.now() - 86400_000).toISOString());
  if (error) throw new Error(error.message);
  return new Set((data ?? []).map((r) => r.fingerprint));
}
