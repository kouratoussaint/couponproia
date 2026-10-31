// Edge Function : synchronisation des données football.
//
// Appelée par pg_cron (en-tête x-cron-secret) ou par un administrateur depuis l'app
// (JWT + permission sports.configure). Le travail s'exécute en arrière-plan ; la
// réponse est immédiate et le résultat est consigné dans la table sync_runs.
import { createClient } from "npm:@supabase/supabase-js@2";
import { ApiFootballProvider } from "../_shared/sports/api_football.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";
import { SportsSync, type SyncJob } from "../_shared/sports/sync.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const JOBS: SyncJob[] = ["daily", "odds", "live", "matchday"];

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function env(...names: string[]): string | undefined {
  for (const n of names) {
    const v = Deno.env.get(n);
    if (v) return v;
  }
  return undefined;
}

async function isAuthorized(req: Request, url: string, anonKey: string): Promise<boolean> {
  const cronSecret = env("CRON_SECRET");
  const header = req.headers.get("x-cron-secret");
  if (cronSecret && header && safeEqual(header, cronSecret)) return true;

  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return false;
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData.user) return false;
  const { data, error } = await userClient.rpc("my_permissions");
  return !error && Array.isArray(data) && data.map(String).includes("sports.configure");
}

function runInBackground(task: Promise<unknown>): void {
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) runtime.waitUntil(task);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = env("SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "server_misconfigured" }, 500);

  if (!(await isAuthorized(req, url, anonKey))) return json({ error: "unauthorized" }, 401);

  let job: SyncJob = "daily";
  try {
    const body = await req.json();
    if (JOBS.includes(body?.job)) job = body.job;
    else return json({ error: "unknown_job", allowed: JOBS }, 400);
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const apiKey = env("API_FOOTBALL_KEY");
  const db = createClient(url, serviceKey, { auth: { persistSession: false } });
  if (!apiKey) {
    await db.from("sync_runs").insert({
      provider_id: "api_football",
      job,
      status: "skipped",
      finished_at: new Date().toISOString(),
      error: "Clé API_FOOTBALL_KEY absente des secrets de la fonction",
    });
    return json({ accepted: false, error: "missing_api_key" }, 503);
  }

  const sync = new SportsSync(db, new ApiFootballProvider(apiKey));
  const task = sync.run(job).then(
    (r) => console.log(JSON.stringify(r)),
    (e) => console.error("sync", e instanceof Error ? e.message : e),
  );
  runInBackground(task);
  return json({ accepted: true, job }, 202);
});
