// Edge Function : suppression définitive du compte de l'utilisateur connecté.
//
// - L'identité vient uniquement du JWT envoyé par l'app (jamais d'un id passé en paramètre).
// - L'utilisateur doit confirmer explicitement en envoyant { "confirmation": "SUPPRIMER" }.
// - La suppression de auth.users entraîne, par cascade, celle du profil, des
//   préférences et des rôles. Le journal d'audit conserve une trace anonymisée.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = Deno.env.get(name);
    if (value) return value;
  }
  throw new Error(`Variable d'environnement manquante : ${names.join(" ou ")}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  let body: { confirmation?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // corps absent ou invalide : traité comme non confirmé
  }
  if (body.confirmation !== "SUPPRIMER") {
    return json({ error: "confirmation_required" }, 400);
  }

  try {
    const url = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY");
    const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY");

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "unauthorized" }, 401);
    const userId = userData.user.id;

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const { error: auditError } = await admin.from("audit_logs").insert({
      actor_id: null,
      action: "account.delete",
      target_type: "user",
      target_id: userId,
      details: { requested_at: new Date().toISOString() },
    });
    if (auditError) console.error("audit", auditError.message);

    // Fichiers de l'utilisateur : logo et couverture du studio (privés), photo de profil Tipster.
    for (const bucket of ["branding", "tipster-avatars"]) {
      const { data: files } = await admin.storage.from(bucket).list(userId, { limit: 100 });
      if (files?.length) {
        const { error: storageError } = await admin.storage.from(bucket).remove(files.map((f) => `${userId}/${f.name}`));
        if (storageError) console.error("storage", bucket, storageError.message);
      }
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("delete", deleteError.message);
      return json({ error: "delete_failed" }, 500);
    }
    return json({ ok: true }, 200);
  } catch (e) {
    console.error(e instanceof Error ? e.message : e);
    return json({ error: "server_error" }, 500);
  }
});
