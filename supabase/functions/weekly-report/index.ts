// Edge Function : rapport hebdomadaire par e-mail (C5). Le lundi à 7 h 05 (pg_cron), envoie à
// chaque utilisateur qui l'a demandé (Notifications → Rapport hebdomadaire par e-mail) son bilan
// des 7 derniers jours et celui de la plateforme. Un super administrateur (ops.monitor) peut
// s'envoyer un aperçu à lui seul : {"preview": true}.
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";
import { sendMail, smtpFromEnv } from "../_shared/email/smtp.ts";
import { type PlatformWeek, type Recipient, weeklyEmail } from "../_shared/email/weekly_mail.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

const MAX_PER_RUN = 300;
const TIME_BUDGET_MS = 100_000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const started = Date.now();
  const cronSecret = env("CRON_SECRET");
  const header = req.headers.get("x-cron-secret");
  const fromCron = Boolean(cronSecret && header && safeEqual(header, cronSecret));
  let previewFor: string | null = null;
  if (!fromCron) {
    const caller = await callerFrom(req, ctx);
    if (!caller) return json({ error: "unauthorized" }, 401);
    if (!caller.permissions.includes("ops.monitor")) return json({ error: "forbidden" }, 403);
    previewFor = caller.id;
  }
  const smtp = smtpFromEnv((k) => Deno.env.get(k));
  if (!smtp) return json({ error: "smtp_not_configured" }, 503);
  try {
    const until = new Date();
    const since = new Date(until.getTime() - 7 * 86400_000);
    const { data, error } = await ctx.db.rpc("svc_weekly_report", {
      p_since: since.toISOString(),
      p_user: previewFor,
    });
    if (error) throw new Error(error.message);
    const report = data as { platform: PlatformWeek; recipients: Recipient[] };
    const settings = await readSettings(ctx.db, ["app.currency"]);
    const cur = (settings["app.currency"] as { label?: string } | undefined)?.label ?? "FCFA";
    let sent = 0;
    const failed: string[] = [];
    for (const r of report.recipients.slice(0, MAX_PER_RUN)) {
      if (Date.now() - started > TIME_BUDGET_MS) break;
      const m = weeklyEmail(r, report.platform, since, until, cur);
      try {
        await sendMail(smtp, { from: smtp.from, fromName: "Coupon Pro IA", to: [r.email], ...m });
        sent++;
        if (!previewFor) {
          await ctx.db.from("user_preferences").update({ weekly_email_sent_at: new Date().toISOString() })
            .eq("user_id", r.user_id);
        }
      } catch (e) {
        failed.push(String((e as Error).message ?? e).slice(0, 120));
      }
    }
    // Les destinataires non servis (budget de temps) le seront à l'appel suivant : la date
    // d'envoi n'est posée qu'après un envoi réussi.
    return json({
      preview: Boolean(previewFor),
      recipients: report.recipients.length,
      sent,
      failed: failed.length,
      error: failed[0] ?? null,
    });
  } catch (e) {
    console.error("weekly-report", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
