// Edge Function : contrôle d'exploitation (toutes les 15 minutes, pg_cron) ou à la demande depuis
// la console (permission ops.monitor). Ouvre et clôt les alertes (public.ops_run_scan, qui prévient
// les super administrateurs par notification), puis envoie un e-mail récapitulatif des nouvelles
// alertes quand un SMTP est configuré (secrets SMTP_*, port 465).
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";
import { sendMail, smtpFromEnv } from "../_shared/email/smtp.ts";
import { alertEmail, type Opened } from "../_shared/email/ops_mail.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const cronSecret = env("CRON_SECRET");
  const header = req.headers.get("x-cron-secret");
  const fromCron = Boolean(cronSecret && header && safeEqual(header, cronSecret));
  if (!fromCron) {
    const caller = await callerFrom(req, ctx);
    if (!caller) return json({ error: "unauthorized" }, 401);
    if (!caller.permissions.includes("ops.monitor")) return json({ error: "forbidden" }, 403);
  }
  try {
    const { data, error } = await ctx.db.rpc("ops_run_scan");
    if (error) throw new Error(error.message);
    const scan = data as { opened: Opened[]; resolved: number; open: number };
    let emailed = 0;
    let emailError: string | null = null;
    const smtp = smtpFromEnv((k) => Deno.env.get(k));
    const settings = await readSettings(ctx.db, ["ops.email_enabled"]);
    if (scan.opened.length && smtp && settings["ops.email_enabled"] !== false) {
      const { data: rows, error: e } = await ctx.db.rpc("ops_recipients");
      if (e) throw new Error(e.message);
      const to = ((rows ?? []) as { email: string }[]).map((r) => r.email).filter(Boolean);
      if (to.length) {
        try {
          const m = alertEmail(scan.opened);
          await sendMail(smtp, { from: smtp.from, fromName: "Coupon Pro IA", to, ...m });
          emailed = to.length;
          await ctx.db.from("ops_alerts").update({ emailed_at: new Date().toISOString() })
            .in("id", scan.opened.map((o) => o.id));
        } catch (err) {
          emailError = String((err as Error).message ?? err).slice(0, 200);
          console.error("ops-monitor email", emailError);
        }
      }
    }
    return json({ opened: scan.opened.length, resolved: scan.resolved, open: scan.open, emailed, email_error: emailError,
      smtp: Boolean(smtp) });
  } catch (e) {
    console.error("ops-monitor", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
