// Edge Function : fournisseurs d'IA (écran du super administrateur, permission ai.providers).
//
//  - « status » : pour chaque fournisseur connu, clé présente ou non (jamais la clé),
//    rôle, modèle, consommation (aujourd'hui, 7 et 30 jours), dernier quota annoncé.
//  - « models » : modèles proposés par le fournisseur, interrogé en direct.
//  - « test » : un appel court qui vérifie la clé et mesure le temps de réponse.
//  - « save » : principale, secours et modèles ; une IA sans clé ne peut pas être choisie.
//    Chaque changement est inscrit au journal d'audit.
import { listModels, makeProvider, PROVIDERS, type Quota } from "../_shared/ai/providers.ts";
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";
import { aggregateUsage, type UsageRow, validateRoles } from "../_shared/ai/roles.ts";

const AI_KEYS = ["ai.provider", "ai.model", "ai.fallback_providers", "ai.models", "ai.pricing_usd_per_mtok", "ai.reference_limits"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const caller = await callerFrom(req, ctx);
  if (!caller) return json({ error: "unauthorized" }, 401);
  if (!caller.permissions.includes("ai.providers")) return json({ error: "forbidden" }, 403);
  const { db } = ctx;
  const body = await req.json().catch(() => ({}));
  const action = String(body?.action ?? "status");
  const configured = (name: string) => Boolean(PROVIDERS[name] && env(PROVIDERS[name].secret));

  try {
    const s = await readSettings(db, AI_KEYS);
    const primary = String(s["ai.provider"] ?? "gemini");
    const fallbacks = Array.isArray(s["ai.fallback_providers"]) ? (s["ai.fallback_providers"] as unknown[]).map(String) : [];
    const models = { ...(s["ai.models"] ?? {}) as Record<string, string> };
    if (s["ai.model"]) models[primary] = String(s["ai.model"]);

    if (action === "status") {
      const since = new Date(Date.now() - 30 * 86400_000).toISOString();
      const rows: UsageRow[] = [];
      for (let from = 0;; from += 1000) {
        const { data, error } = await db.from("ai_requests")
          .select("provider, status, input_tokens, output_tokens, cost_usd, latency_ms, error, created_at, quota")
          .gte("created_at", since).not("provider", "is", null)
          .order("created_at", { ascending: false }).range(from, from + 999);
        if (error) throw new Error(error.message);
        rows.push(...(data ?? []) as UsageRow[]);
        if ((data ?? []).length < 1000) break;
      }
      const timeZone = "Africa/Ouagadougou";
      const usage = aggregateUsage(rows, new Date(), timeZone);
      const limits = (s["ai.reference_limits"] ?? {}) as Record<string, unknown>;
      return json({
        providers: Object.entries(PROVIDERS).map(([name, p]) => ({
          name,
          label: p.label,
          secret: p.secret,
          configured: configured(name),
          role: name === primary ? "primary" : fallbacks.includes(name) ? `fallback_${fallbacks.indexOf(name) + 1}` : "disabled",
          model: models[name] ?? null,
          usage: usage[name] ?? null,
          reference_limits: limits[name] ?? null,
        })),
        pricing: s["ai.pricing_usd_per_mtok"] ?? {},
      });
    }

    if (action === "models") {
      const name = String(body?.provider ?? "");
      if (!configured(name)) return json({ error: "provider_not_configured" }, 400);
      return json({ provider: name, models: await listModels(name, env(PROVIDERS[name].secret)!) });
    }

    if (action === "test") {
      const name = String(body?.provider ?? "");
      const model = String(body?.model ?? models[name] ?? "");
      const provider = makeProvider(name, (k) => env(k));
      if (!provider) return json({ error: "provider_not_configured" }, 400);
      if (!model) return json({ error: "model_missing" }, 400);
      const started = Date.now();
      let ok = false;
      let error: string | null = null;
      let quota: Quota | null = null;
      let usedModel = model;
      let tokens: [number | null, number | null] = [null, null];
      try {
        const res = await provider.call(
          'Réponds uniquement par cet objet JSON : {"ok": true}',
          "Test de connexion de Coupon Pro IA.",
          model,
        );
        ok = res.text.includes("ok");
        if (!ok) error = "réponse inattendue";
        quota = res.quota ?? null;
        usedModel = res.model;
        tokens = [res.inputTokens, res.outputTokens];
      } catch (e) {
        error = String((e as Error).message ?? e).slice(0, 300);
        quota = (e as { quota?: Quota | null }).quota ?? null;
      }
      const latency = Date.now() - started;
      await db.from("ai_requests").insert({
        user_id: caller.id,
        kind: "provider_test",
        provider: name,
        model: usedModel,
        status: ok ? "success" : "error",
        attempts: 1,
        input_tokens: tokens[0],
        output_tokens: tokens[1],
        latency_ms: latency,
        error,
        quota,
      });
      return json({ provider: name, model: usedModel, ok, latency_ms: latency, error, quota });
    }

    if (action === "save") {
      const wanted = {
        primary: String(body?.primary ?? ""),
        fallbacks: Array.isArray(body?.fallbacks) ? body.fallbacks.map(String) : [],
        models: (body?.models && typeof body.models === "object" ? body.models : {}) as Record<string, unknown>,
      };
      const v = validateRoles(wanted, configured, Object.keys(PROVIDERS));
      if (!v.ok) return json({ error: "invalid_roles", message: v.message }, 400);
      const next = { ...models, ...v.models };
      const before = { primary, fallbacks, models };
      const updates: [string, unknown][] = [
        ["ai.provider", v.primary],
        ["ai.model", next[v.primary]],
        ["ai.fallback_providers", v.fallbacks],
        ["ai.models", next],
      ];
      for (const [key, value] of updates) {
        const { error } = await db.from("app_settings").update({ value }).eq("key", key);
        if (error) throw new Error(error.message);
      }
      await db.from("audit_logs").insert({
        actor_id: caller.id,
        action: "ai.providers.update",
        target_type: "setting",
        target_id: "ai.provider",
        details: { old: before, new: { primary: v.primary, fallbacks: v.fallbacks, models: next } },
      });
      return json({ ok: true, primary: v.primary, fallbacks: v.fallbacks, models: next });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
