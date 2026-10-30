// Edge Function : « Analyser avec l'IA ».
//
// 1. Fiche statistique calculée par le moteur (données réelles antérieures au match).
// 2. Interprétation par l'IA, validée par des garde-fous (aucun chiffre inventé,
//    aucun mot de certitude) ; à défaut, la fiche seule est renvoyée (« stats_only »).
// Une analyse est partagée entre utilisateurs et mise en cache : un match = un coût.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { analyzeWithAi, type Pricing, type ProviderChoice } from "../_shared/ai/analyst.ts";
import { makeProvider } from "../_shared/ai/providers.ts";
import { buildFiche, type NamedMatch, type OddsRow } from "../_shared/engine/fiche.ts";
import { ENGINE_VERSION, type PlayedMatch } from "../_shared/engine/poisson.ts";
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";

const PLAYED = ["finished", "awarded"];
const ANALYSIS_COLUMNS =
  "id, match_id, engine_version, prompt_key, prompt_version, provider, model, status, status_reason, stats, analysis, source_updated_at, created_at";
const STATS_ONLY_TTL_MS = 60 * 60 * 1000;

interface MatchRow {
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

async function loadFicheInputs(db: SupabaseClient, m: MatchRow) {
  const played = () =>
    db.from("matches").select(PLAYED_COLUMNS).in("status", PLAYED).lt("kickoff_at", m.kickoff_at)
      .not("home_goals", "is", null).not("away_goals", "is", null);

  const homeId = m.home!.id;
  const awayId = m.away!.id;
  const [history, recentHome, recentAway, h2h, odds] = await Promise.all([
    db.from("matches").select("kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
      .eq("competition_id", m.competition!.id).eq("season", m.season).in("status", PLAYED)
      .lt("kickoff_at", m.kickoff_at).not("home_goals", "is", null).not("away_goals", "is", null)
      .order("kickoff_at").limit(1000),
    played().or(`home_team_id.eq.${homeId},away_team_id.eq.${homeId}`).order("kickoff_at", { ascending: false }).limit(5),
    played().or(`home_team_id.eq.${awayId},away_team_id.eq.${awayId}`).order("kickoff_at", { ascending: false }).limit(5),
    played().or(
      `and(home_team_id.eq.${homeId},away_team_id.eq.${awayId}),and(home_team_id.eq.${awayId},away_team_id.eq.${homeId})`,
    ).order("kickoff_at", { ascending: false }).limit(5),
    db.from("latest_odds").select("market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at")
      .eq("match_id", m.id),
  ]);
  for (const r of [history, recentHome, recentAway, h2h, odds]) {
    if (r.error) throw new Error(r.error.message);
  }
  return {
    history: (history.data as unknown as RawPlayed[]).map(toPlayed),
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

function isFresh(cached: { status: string; engine_version: string; created_at: string }, played: boolean, ttlHours: number) {
  if (cached.engine_version !== ENGINE_VERSION) return false;
  const age = Date.now() - Date.parse(cached.created_at);
  if (cached.status === "stats_only") return age < STATS_ONLY_TTL_MS;
  return played || age < ttlHours * 3600_000;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const caller = await callerFrom(req, ctx);
  if (!caller) return json({ error: "unauthorized" }, 401);

  let matchId: number;
  let force = false;
  try {
    const body = await req.json();
    matchId = Number(body?.match_id);
    force = body?.force === true;
    if (!Number.isInteger(matchId) || matchId <= 0) return json({ error: "invalid_match_id" }, 400);
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const { db } = ctx;
  const canManage = caller.permissions.includes("ai.configure");
  if (force && !canManage) return json({ error: "forbidden" }, 403);

  try {
    const { data: flag } = await db.from("feature_flags").select("enabled").eq("key", "match_analysis").maybeSingle();
    if (!flag?.enabled) return json({ error: "feature_disabled" }, 403);

    const { data: match, error: matchError } = await db.from("matches").select(
      "id, season, round, kickoff_at, status, competition:competitions(id, name, type), home:teams!matches_home_team_fk(id, name), away:teams!matches_away_team_fk(id, name)",
    ).eq("id", matchId).maybeSingle();
    if (matchError) throw new Error(matchError.message);
    if (!match) return json({ error: "match_not_found" }, 404);
    const m = match as unknown as MatchRow;
    if (!m.competition || !m.home || !m.away) return json({ error: "match_incomplete" }, 422);
    if (["postponed", "cancelled", "abandoned"].includes(m.status)) return json({ error: "match_not_analyzable" }, 422);
    const played = PLAYED.includes(m.status);

    const settings = await readSettings(db, [
      "ai.provider",
      "ai.model",
      "ai.fallback_providers",
      "ai.models",
      "ai.pricing_usd_per_mtok",
      "ai.max_new_analyses_per_user_day",
      "ai.analysis_ttl_hours",
    ]);
    const ttlHours = Number(settings["ai.analysis_ttl_hours"] ?? 12);

    if (!force) {
      const { data: cached } = await db.from("match_analyses").select(ANALYSIS_COLUMNS).eq("match_id", matchId)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (cached && isFresh(cached, played, ttlHours)) return json({ ...cached, cached: true });
    }

    // Quota : nouvelles analyses déclenchées par l'utilisateur aujourd'hui (UTC = heure de Ouagadougou).
    const limit = Number(settings["ai.max_new_analyses_per_user_day"] ?? 20);
    if (!canManage) {
      const dayStart = new Date();
      dayStart.setUTCHours(0, 0, 0, 0);
      const { data: today } = await db.from("ai_requests").select("match_id").eq("user_id", caller.id)
        .eq("kind", "match_analysis").gte("created_at", dayStart.toISOString()).limit(500);
      const used = new Set((today ?? []).map((r) => r.match_id)).size;
      if (used >= limit) return json({ error: "daily_limit", limit }, 429);
    }

    const inputs = await loadFicheInputs(db, m);
    const { data: evaluation } = await db.from("engine_evaluations")
      .select("matches_evaluated, brier_model, brier_baseline, details")
      .eq("engine_version", ENGINE_VERSION).order("created_at", { ascending: false }).limit(1).maybeSingle();
    const quality = evaluation
      ? {
        evaluatedMatches: evaluation.matches_evaluated,
        beatsBaseline: {
          "1X2": Number(evaluation.brier_model) < Number(evaluation.brier_baseline),
          OU: Number(evaluation.details?.over_2_5?.brierModel) < Number(evaluation.details?.over_2_5?.brierBaseline),
          BTTS: Number(evaluation.details?.btts?.brierModel) < Number(evaluation.details?.btts?.brierBaseline),
        },
      }
      : null;
    const fiche = buildFiche({
      match: {
        id: m.id,
        kickoffAt: m.kickoff_at,
        season: m.season,
        round: m.round,
        competition: m.competition,
        home: m.home,
        away: m.away,
      },
      ...inputs,
      quality,
      generatedAt: new Date().toISOString(),
    });

    const { data: prompt } = await db.from("ai_prompts").select("key, version, system_prompt")
      .eq("key", "match_analysis").eq("is_active", true).maybeSingle();

    const primary = String(settings["ai.provider"] ?? "gemini");
    const fallbacks = Array.isArray(settings["ai.fallback_providers"]) ? settings["ai.fallback_providers"] as string[] : [];
    const models = (settings["ai.models"] ?? {}) as Record<string, string>;
    const choices: ProviderChoice[] = [];
    for (const name of [primary, ...fallbacks.filter((f) => f !== primary)]) {
      const provider = makeProvider(name, (k) => env(k));
      const model = name === primary ? String(settings["ai.model"] ?? "") : models[name];
      if (provider && model) choices.push({ provider, model });
    }

    const result = prompt
      ? await analyzeWithAi(fiche, prompt.system_prompt, choices, (settings["ai.pricing_usd_per_mtok"] ?? {}) as Pricing)
      : { status: "stats_only" as const, reason: "no_prompt", logs: [] };

    const sourceUpdatedAt = [inputs.history.at(-1)?.kickoffAt, fiche.market.captured_at].filter(Boolean).sort().at(-1) ??
      m.kickoff_at;
    const { data: saved, error: saveError } = await db.from("match_analyses").insert({
      match_id: m.id,
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
      user_id: caller.id,
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
    })));

    return json({ ...saved, cached: false });
  } catch (e) {
    console.error("analyze-match", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
