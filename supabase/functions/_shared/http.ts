// Outils communs des Edge Functions : CORS, réponses JSON, variables d'environnement,
// identification de l'utilisateur et de ses permissions.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

export function env(...names: string[]): string | undefined {
  for (const n of names) {
    const v = Deno.env.get(n);
    if (v) return v;
  }
  return undefined;
}

export interface ServerContext {
  url: string;
  anonKey: string;
  db: SupabaseClient;
}

export function serverContext(): ServerContext | null {
  const url = env("SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY");
  if (!url || !anonKey || !serviceKey) return null;
  return { url, anonKey, db: createClient(url, serviceKey, { auth: { persistSession: false } }) };
}

export interface Caller {
  id: string;
  permissions: string[];
}

/** Utilisateur connecté (jeton de l'en-tête Authorization) et ses permissions, ou null. */
export async function callerFrom(req: Request, ctx: ServerContext): Promise<Caller | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const userClient = createClient(ctx.url, ctx.anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData.user) return null;
  const { data } = await userClient.rpc("my_permissions");
  return { id: userData.user.id, permissions: Array.isArray(data) ? data.map(String) : [] };
}

/** Lit des réglages app_settings (clé → valeur JSON). */
export async function readSettings(db: SupabaseClient, keys: string[]): Promise<Record<string, unknown>> {
  const { data, error } = await db.from("app_settings").select("key, value").in("key", keys);
  if (error) throw new Error(`app_settings : ${error.message}`);
  return Object.fromEntries((data ?? []).map((r) => [r.key, r.value] as [string, unknown]));
}
