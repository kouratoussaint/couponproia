// Edge Function : « Analyser avec l'IA ».
//
// 1. Fiche statistique calculée par le moteur (données réelles antérieures au match).
// 2. Interprétation par l'IA, validée par des garde-fous (aucun chiffre inventé,
//    aucun mot de certitude) ; à défaut, la fiche seule est renvoyée (« stats_only »).
// Une analyse est partagée entre utilisateurs et mise en cache : un match = un coût.
// Le match offert du jour ne compte pas dans le quota quotidien.
import { ANALYSIS_COLUMNS, generateMatchAnalysis, isFresh, MATCH_COLUMNS, type MatchRow, PLAYED } from "../_shared/analysis/generate.ts";
import { planFeatures } from "../_shared/billing.ts";
import { analysisAllowed } from "../_shared/analysis/access.ts";
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
    ]);
    const ttlHours = Number(settings["ai.analysis_ttl_hours"] ?? 12);

    const { data: prompt } = await db.from("ai_prompts").select("key, version, system_prompt")
      .eq("key", "match_analysis").eq("is_active", true).maybeSingle();

    if (!force) {
      const { data: cached } = await db.from("match_analyses").select(ANALYSIS_COLUMNS).eq("match_id", matchId)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (cached && isFresh(cached, played, ttlHours, prompt?.version ?? null)) return json({ ...forCaller(cached), cached: true });
    }

    // Quota : nouvelles analyses déclenchées par l'utilisateur aujourd'hui (UTC = heure de Ouagadougou).
    // Limite selon le forfait (réglage pricing.plans), à défaut le réglage général.
    const { features } = await planFeatures(db, caller.id);
    const limit = Number(features.match_analyses_per_day ?? settings["ai.max_new_analyses_per_user_day"] ?? 20);
    const { data: featured } = await db.from("featured_matches").select("match_id").eq("match_id", m.id)
      .gte("day", new Date(Date.now() - 36 * 3600_000).toISOString().slice(0, 10)).limit(1).maybeSingle();
    // Nouvelle analyse : réservée aux comptes avec un forfait payant ou des crédits (l'analyse
    // offerte du jour reste ouverte à tous). Les analyses déjà réalisées restent consultables.
    if (!canManage && !featured) {
      const { data: summary } = await db.rpc("svc_credit_summary", { p_user: caller.id });
      if (!analysisAllowed(summary)) return json({ error: "subscription_required" }, 402);
    }
    if (!canManage && !featured) {
      const dayStart = new Date();
      dayStart.setUTCHours(0, 0, 0, 0);
      const { data: today } = await db.from("ai_requests").select("match_id").eq("user_id", caller.id)
        .eq("kind", "match_analysis").gte("created_at", dayStart.toISOString()).limit(500);
      // Les analyses offertes ne comptent pas.
      const { data: offered } = await db.from("featured_matches").select("match_id")
        .in("match_id", [...new Set((today ?? []).map((r) => r.match_id))].filter((x) => x !== null));
      const free = new Set((offered ?? []).map((r) => r.match_id));
      const used = new Set((today ?? []).map((r) => r.match_id).filter((x) => !free.has(x))).size;
      if (used >= limit) return json({ error: "daily_limit", limit }, 429);
    }

    const saved = await generateMatchAnalysis(db, m, prompt, caller.id);
    return json({ ...forCaller(saved), cached: false });
  } catch (e) {
    console.error("analyze-match", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});

