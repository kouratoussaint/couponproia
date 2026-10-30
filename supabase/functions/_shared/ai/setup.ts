// Fournisseurs IA configurés (réglages ai.* + clés présentes) et grille de prix.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Pricing, ProviderChoice } from "./analyst.ts";
import { makeProvider } from "./providers.ts";

export async function loadAiSetup(
  db: SupabaseClient,
  env: (key: string) => string | undefined,
): Promise<{ choices: ProviderChoice[]; pricing: Pricing }> {
  const { data } = await db.from("app_settings").select("key, value")
    .in("key", ["ai.provider", "ai.model", "ai.fallback_providers", "ai.models", "ai.pricing_usd_per_mtok"]);
  const s = Object.fromEntries((data ?? []).map((r) => [r.key, r.value] as [string, unknown]));
  const primary = String(s["ai.provider"] ?? "gemini");
  const fallbacks = Array.isArray(s["ai.fallback_providers"]) ? s["ai.fallback_providers"] as string[] : [];
  const models = (s["ai.models"] ?? {}) as Record<string, string>;
  const choices: ProviderChoice[] = [];
  for (const name of [primary, ...fallbacks.filter((f) => f !== primary)]) {
    const provider = makeProvider(name, env);
    const model = name === primary ? String(s["ai.model"] ?? "") : models[name];
    if (provider && model) choices.push({ provider, model });
  }
  return { choices, pricing: (s["ai.pricing_usd_per_mtok"] ?? {}) as Pricing };
}
