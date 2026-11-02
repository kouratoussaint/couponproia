// Génération d'une analyse de match (fiche du moteur + texte de l'IA vérifié), partagée par
// analyze-match (demande d'un utilisateur) et le moteur de coupons (analyse offerte du jour).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { analyzeWithAi } from "../ai/analyst.ts";
import { withLanguage } from "../ai/language.ts";
import type { Lang } from "../lang.ts";
import { loadAiSetup } from "../ai/setup.ts";
import { loadEngineQuality } from "../engine/quality.ts";
import { buildFiche, type NamedMatch, type OddsRow } from "../engine/fiche.ts";
import { ENGINE_VERSION, type PlayedMatch, PRIOR_SEASON_WEIGHT, weighted } from "../engine/poisson.ts";
import { env } from "../http.ts";

export const MATCH_COLUMNS =
  "id, season, round, kickoff_at, status, competition:competitions(id, name, type), home:teams!matches_home_team_fk(id, name), away:teams!matches_away_team_fk(id, name)";

export const PLAYED = ["finished", "awarded"];
export const ANALYSIS_COLUMNS =
  "id, match_id, language, engine_version, prompt_key, prompt_version, provider, model, status, status_reason, stats, analysis, source_updated_at, created_at";
const STATS_ONLY_TTL_MS = 60 * 60 * 1000;

export interface MatchRow {
  id: number;
  season: number;
  round: string | null;
  kickoff_at: string;
  status: string;
  competition: { id: number; name: string; type: string | null } | null;
  home: { id: number; name: string } | null;
  away: { id: number; name: string } | null;
}

interface RawPlayed {
  kickoff_at: string;
  home_team_id: number;
  away_team_id: number;
  home_goals: number;
  away_goals: number;
  home?: { name: string } | null;
  away?: { name: string } | null;
  competition?: { name: string } | null;
}

const toPlayed = (r: RawPlayed): PlayedMatch => ({
  kickoffAt: r.kickoff_at,
  homeId: r.home_team_id,
  awayId: r.away_team_id,
  homeGoals: r.home_goals,
  awayGoals: r.away_goals,
});
const toNamed = (r: RawPlayed): NamedMatch => ({
  ...toPlayed(r),
  homeName: r.home?.name ?? "?",
  awayName: r.away?.name ?? "?",
  competitionName: r.competition?.name,
});

const PLAYED_COLUMNS =
  "kickoff_at, home_team_id, away_team_id, home_goals, away_goals, home:teams!matches_home_team_fk(name), away:teams!matches_away_team_fk(name), competition:competitions(name)";

export async function loadFicheInputs(db: SupabaseClient, m: MatchRow) {
  const played = () =>
    db.from("matches").select(PLAYED_COLUMNS).in("status", PLAYED).lt("kickoff_at", m.kickoff_at)
      .not("home_goals", "is", null).not("away_goals", "is", null);

  const homeId = m.home!.id;
  const awayId = m.away!.id;
  const [history, prior, recentHome, recentAway, h2h, odds] = await Promise.all([
    db.from("matches").select("kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
      .eq("competition_id", m.competition!.id).eq("season", m.season).in("status", PLAYED)
      .lt("kickoff_at", m.kickoff_at).not("home_goals", "is", null).not("away_goals", "is", null)
      .order("kickoff_at").limit(1000),
    db.from("matches").select("kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
      .eq("competition_id", m.competition!.id).eq("season", m.season - 1).in("status", PLAYED)
      .not("home_goals", "is", null).not("away_goals", "is", null)
      .order("kickoff_at").limit(1000),
    played().or(`home_team_id.eq.${homeId},away_team_id.eq.${homeId}`).order("kickoff_at", { ascending: false }).limit(5),
    played().or(`home_team_id.eq.${awayId},away_team_id.eq.${awayId}`).order("kickoff_at", { ascending: false }).limit(5),
    played().or(
      `and(home_team_id.eq.${homeId},away_team_id.eq.${awayId}),and(home_team_id.eq.${awayId},away_team_id.eq.${homeId})`,
    ).order("kickoff_at", { ascending: false }).limit(5),
    db.from("latest_odds").select("market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at")
      .eq("match_id", m.id),
  ]);
  for (const r of [history, prior, recentHome, recentAway, h2h, odds]) {
    if (r.error) throw new Error(r.error.message);
  }
  return {
    history: (history.data as unknown as RawPlayed[]).map(toPlayed),
    prior: weighted((prior.data as unknown as RawPlayed[]).map(toPlayed), PRIOR_SEASON_WEIGHT),
    recentHome: (recentHome.data as unknown as RawPlayed[]).map(toNamed),
    recentAway: (recentAway.data as unknown as RawPlayed[]).map(toNamed),
    headToHead: (h2h.data as unknown as RawPlayed[]).map(toNamed),
    odds: (odds.data ?? []).map((o) => ({
      ...o,
      line: o.line === null ? null : Number(o.line),
      odd_median: Number(o.odd_median),
      odd_best: Number(o.odd_best),
    })) as OddsRow[],
  };
}

export function isFresh(
  cached: { status: string; engine_version: string; prompt_version: number | null; created_at: string },
  played: boolean,
  ttlHours: number,
  promptVersion: number | null,
) {
  if (cached.engine_version !== ENGINE_VERSION) return false;
  // Nouveau prompt (consignes corrigées) : l'ancien texte n'est plus servi.
  if (cached.status === "ok" && promptVersion !== null && cached.prompt_version !== promptVersion) return false;
  const age = Date.now() - Date.parse(cached.created_at);
  if (cached.status === "stats_only") return age < STATS_ONLY_TTL_MS;
  return played || age < ttlHours * 3600_000;
}


/** Calcule et enregistre une nouvelle analyse ; renvoie la ligne enregistrée. */
export async function generateMatchAnalysis(
  db: SupabaseClient,
  m: MatchRow,
  prompt: { key: string; version: number; system_prompt: string } | null,
  userId: string | null,
  lang: Lang = "fr",
) {
  const inputs = await loadFicheInputs(db, m);
  const quality = await loadEngineQuality(db);
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
    ...inputs,
    quality,
    generatedAt: new Date().toISOString(),
    lang,
  });


  const { choices, pricing } = await loadAiSetup(db, (k) => env(k));

  const result = prompt
    ? await analyzeWithAi(fiche, withLanguage(prompt.system_prompt, lang), choices, pricing)
    : { status: "stats_only" as const, reason: "no_prompt", logs: [] };

  const sourceUpdatedAt = [inputs.history.at(-1)?.kickoffAt, fiche.market.captured_at].filter(Boolean).sort().at(-1) ??
    m.kickoff_at;
  const { data: saved, error: saveError } = await db.from("match_analyses").insert({
    match_id: m.id,
    language: lang,
    engine_version: ENGINE_VERSION,
    prompt_key: prompt?.key ?? null,
    prompt_version: prompt?.version ?? null,
    provider: result.status === "ok" ? result.provider : null,
    model: result.status === "ok" ? result.model : null,
    status: result.status,
    status_reason: result.status === "ok" ? null : result.reason,
    stats: fiche,
    analysis: result.status === "ok" ? result.analysis : null,
    source_updated_at: sourceUpdatedAt,
  }).select(ANALYSIS_COLUMNS).single();
  if (saveError) throw new Error(saveError.message);

  const logs = result.logs.length > 0 ? result.logs : [null];
  await db.from("ai_requests").insert(logs.map((l) => ({
    user_id: userId,
    kind: "match_analysis",
    match_id: m.id,
    provider: l?.provider ?? null,
    model: l?.model ?? null,
    status: l?.status ?? "stats_only",
    attempts: l?.attempts ?? 0,
    input_tokens: l?.inputTokens ?? null,
    output_tokens: l?.outputTokens ?? null,
    cost_usd: l?.costUsd ?? null,
    latency_ms: l?.latencyMs ?? null,
    error: l?.error ?? (result.status === "stats_only" ? result.reason : null),
    quota: l?.quota ?? null,
  })));

  return saved;
}

/** Dernière analyse encore valable pour ce match, sinon null. */
export async function freshAnalysis(
  db: SupabaseClient,
  m: MatchRow,
  ttlHours: number,
  promptVersion: number | null,
  lang: Lang = "fr",
) {
  const { data: cached } = await db.from("match_analyses").select(ANALYSIS_COLUMNS).eq("match_id", m.id).eq("language", lang)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  return cached && isFresh(cached, PLAYED.includes(m.status), ttlHours, promptVersion) ? cached : null;
}
