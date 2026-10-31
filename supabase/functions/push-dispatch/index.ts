// Edge Function : envoi des notifications en attente sur les téléphones (FCM).
// Appelée par pg_cron toutes les 2 minutes (secret partagé). Sans compte de service Firebase,
// les notifications restent dans la boîte de réception de l'app et sont marquées « skipped ».
import { env, json, serverContext } from "../_shared/http.ts";
import { accessToken, parseServiceAccount, sendToToken } from "../_shared/push/fcm.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

const BATCH = 300;
const MAX_ATTEMPTS = 3;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const cronSecret = env("CRON_SECRET");
  const header = req.headers.get("x-cron-secret");
  if (!cronSecret || !header || !safeEqual(header, cronSecret)) return json({ error: "unauthorized" }, 401);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const { db } = ctx;

  const { data: pending, error } = await db.from("notifications")
    .select("id, user_id, kind, title, body, route, push_attempts")
    .eq("push_status", "pending").lte("send_after", new Date().toISOString())
    .order("id").limit(BATCH);
  if (error) return json({ error: error.message }, 500);
  if (!pending?.length) return json({ sent: 0 });

  const sa = parseServiceAccount(env("FCM_SERVICE_ACCOUNT"));
  if (!sa) {
    await db.from("notifications").update({ push_status: "skipped", push_error: "fcm_not_configured" })
      .in("id", pending.map((n) => n.id));
    return json({ sent: 0, skipped: pending.length, reason: "fcm_not_configured" });
  }

  const users = [...new Set(pending.map((n) => n.user_id))];
  const { data: tokens } = await db.from("device_tokens").select("token, user_id").in("user_id", users);
  const byUser = new Map<string, string[]>();
  for (const t of tokens ?? []) byUser.set(t.user_id, [...(byUser.get(t.user_id) ?? []), t.token]);

  let bearer: string;
  try {
    bearer = await accessToken(sa);
  } catch (e) {
    console.error("push-dispatch oauth", e);
    return json({ error: "oauth_failed" }, 502);
  }

  let sent = 0, skipped = 0, failed = 0;
  const dead = new Set<string>();
  for (const n of pending) {
    const userTokens = (byUser.get(n.user_id) ?? []).filter((t) => !dead.has(t));
    if (!userTokens.length) {
      skipped++;
      await db.from("notifications").update({ push_status: "skipped", push_error: "no_device" }).eq("id", n.id);
      continue;
    }
    let delivered = false;
    let lastError = "";
    for (const token of userTokens) {
      const r = await sendToToken(sa.project_id, bearer, token, {
        id: n.id, kind: n.kind, title: n.title, body: n.body, route: n.route,
      });
      if (r.ok) delivered = true;
      else {
        lastError = r.error;
        if (r.unregistered) dead.add(token);
      }
    }
    const attempts = (n.push_attempts ?? 0) + 1;
    if (delivered) sent++;
    else failed++;
    await db.from("notifications").update({
      push_status: delivered ? "sent" : attempts >= MAX_ATTEMPTS ? "failed" : "pending",
      push_attempts: attempts,
      push_error: delivered ? null : lastError.slice(0, 300),
    }).eq("id", n.id);
  }
  if (dead.size) await db.from("device_tokens").delete().in("token", [...dead]);
  return json({ sent, skipped, failed, removed_tokens: dead.size });
});
