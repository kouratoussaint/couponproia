// Forfait effectif d'un utilisateur (abonnement en cours, sinon FREE) et ses avantages.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export async function planFeatures(db: SupabaseClient, userId: string): Promise<{ plan: string; features: Record<string, unknown> }> {
  const nowIso = new Date().toISOString();
  const { data: sub } = await db.from("subscriptions").select("plan_code").eq("user_id", userId)
    .lte("period_start", nowIso).gt("period_end", nowIso).order("period_end", { ascending: false }).limit(1).maybeSingle();
  const plan = sub?.plan_code ?? "FREE";
  const { data: setting } = await db.from("app_settings").select("value").eq("key", "pricing.plans").maybeSingle();
  const entry = Array.isArray(setting?.value) ? (setting!.value as { code: string; features?: Record<string, unknown> }[]).find((p) => p.code === plan) : null;
  return { plan, features: entry?.features ?? {} };
}
