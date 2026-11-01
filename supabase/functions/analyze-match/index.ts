// Edge Function : « Analyser avec l'IA ».
//
// 1. Fiche statistique calculée par le moteur (données réelles antérieures au match).
// 2. Interprétation par l'IA, validée par des garde-fous (aucun chiffre inventé,
//    aucun mot de certitude) ; à défaut, la fiche seule est renvoyée (« stats_only »).
// L'analyse est mise en cache (un match = un coût d'IA) mais son accès est personnel (01/11) :
// chacun ne lit que les analyses qu'il a demandées (forfait payant : quota par jour ; FREE :
// crédits), sauf l'analyse offerte du jour (ouverte à tous) et le super administrateur.
import { ANALYSIS_COLUMNS, generateMatchAnalysis, isFresh, MATCH_COLUMNS, type MatchRow, PLAYED } from "../_shared/analysis/generate.ts";
import { planFeatures } from "../_shared/billing.ts";
import { analysisDecision } from "../_shared/analysis/access.ts";
import { callerFrom, corsHeaders, json, readSettings, serverContext } from "../_shared/http.ts";

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
  // Fournisseur, modèle et prompt : visibles du seul super administrateur (permission ai.providers).
  const forCaller = (row: Record<string, unknown>) => {
    if (caller.permissions.includes("ai.providers")) return row;
    const { provider: _p, model: _m, prompt_key: _k, prompt_version: _v, ...rest } = row;
    return rest;
  };
  if (force && !canManage) return json({ error: "forbidden" }, 403);

  try {
    const { data: flag } = await db.from("feature_flags").select("enabled").eq("key", "match_analysis").maybeSingle();
    if (!flag?.enabled) return json({ error: "feature_disabled" }, 403);

    const { data: match, error: matchError } = await db.from("matches").select(MATCH_COLUMNS).eq("id", matchId)
      .maybeSingle();
    if (matchError) throw new Error(matchError.message);
    if (!match) return json({ error: "match_not_found" }, 404);
    const m = match as unknown as MatchRow;
    if (!m.competition || !m.home || !m.away) return json({ error: "match_incomplete" }, 422);
    if (["postponed", "cancelled", "abandoned"].includes(m.status)) return json({ error: "match_not_analyzable" }, 422);
    const played = PLAYED.includes(m.status);

    const settings = await readSettings(db, [
      "ai.max_new_analyses_per_user_day",
      "ai.analysis_ttl_hours",
      "analysis.credit_cost",
    ]);
    const ttlHours = Number(settings["ai.analysis_ttl_hours"] ?? 12);

    const { data: prompt } = await db.from("ai_prompts").select("key, version, system_prompt")
      .eq("key", "match_analysis").eq("is_active", true).maybeSingle();

    // Accès déjà acquis : son analyse, l'analyse offerte, l'équipe.
    const { data: featured } = await db.from("featured_matches").select("match_id").eq("match_id", m.id)
      .gte("day", new Date(Date.now() - 36 * 3600_000).toISOString().slice(0, 10)).limit(1).maybeSingle();
    const { data: access } = await db.from("analysis_access").select("match_id").eq("user_id", caller.id)
      .eq("match_id", m.id).maybeSingle();
    const unlocked = Boolean(access || featured || canManage || caller.permissions.includes("analyses.read_all"));

    // Nouvel accès : quota du forfait payant, ou crédits avec le forfait FREE.
    let decision: { source: "plan" | "credit"; cost: number } | null = null;
    if (!unlocked) {
      const { plan, features } = await planFeatures(db, caller.id);
      const { data: summary } = await db.rpc("svc_credit_summary", { p_user: caller.id });
      const dayStart = new Date();
      dayStart.setUTCHours(0, 0, 0, 0);
      const { count } = await db.from("analysis_access").select("match_id", { count: "exact", head: true })
        .eq("user_id", caller.id).eq("source", "plan").gte("created_at", dayStart.toISOString());
      const limit = Number(features.match_analyses_per_day ?? settings["ai.max_new_analyses_per_user_day"] ?? 20);
      const d = analysisDecision(summary, plan, count ?? 0, limit, Number(settings["analysis.credit_cost"] ?? 1));
      if (!d.ok) {
        return d.error === "daily_limit"
          ? json({ error: "daily_limit", limit: d.limit }, 429)
          : json({ error: "credits_required", cost: d.cost }, 402);
      }
      decision = d;
    }

    let result: Record<string, unknown> | null = null;
    let fromCache = false;
    if (!force) {
      const { data: cached } = await db.from("match_analyses").select(ANALYSIS_COLUMNS).eq("match_id", matchId)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (cached && isFresh(cached, played, ttlHours, prompt?.version ?? null)) {
        result = cached;
        fromCache = true;
      }
    }
    if (!result) result = await generateMatchAnalysis(db, m, prompt, caller.id);

    if (decision) {
      // Accès personnel, puis débit des crédits (FREE) ; sans crédit au moment du débit, rien n'est ouvert.
      const { data: granted } = await db.from("analysis_access")
        .upsert({ user_id: caller.id, match_id: m.id, source: decision.source }, { onConflict: "user_id,match_id", ignoreDuplicates: true })
        .select("match_id");
      if ((granted ?? []).length && decision.cost > 0) {
        const { error: chargeError } = await db.rpc("svc_consume_credits", {
          p_user: caller.id,
          p_operation: crypto.randomUUID(),
          p_amount: decision.cost,
          p_kind: `analysis:${m.id}`,
        });
        if (chargeError) {
          await db.from("analysis_access").delete().eq("user_id", caller.id).eq("match_id", m.id);
          return json({ error: "credits_required", cost: decision.cost }, 402);
        }
      }
    }
    return json({ ...forCaller(result), cached: fromCache, credits_used: decision?.cost ?? 0 });
  } catch (e) {
    console.error("analyze-match", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});

