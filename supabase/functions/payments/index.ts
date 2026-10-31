// Edge Function : achats (abonnement mensuel ou annuel, packs de crédits).
//  - checkout (utilisateur) : prix calculé ici, paiement créé, lien de l'agrégateur renvoyé ;
//  - status (utilisateur) : relit le statut chez l'agrégateur après le retour dans l'app ;
//  - reconcile (pg_cron) : relit les paiements en attente (notification perdue).
// Aucun droit n'est accordé sans confirmation de l'agrégateur.
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";
import { applyPromo, creditsPrice, newTransactionId, PaymentProviderError, type PlanSetting, subscriptionPrice } from "../_shared/payments/provider.ts";
import { type PaymentRow, providerFromEnv, syncPayment } from "../_shared/payments/service.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

const COLUMNS = "id, user_id, transaction_id, amount_xof, currency, status, fulfilled_at";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const { db, url } = ctx;
  const body = await req.json().catch(() => ({}));
  const action = String(body?.action ?? "");
  const provider = providerFromEnv((k) => env(k));

  try {
    if (action === "reconcile") {
      const secret = env("CRON_SECRET");
      const header = req.headers.get("x-cron-secret");
      if (!(secret && header && safeEqual(header, secret))) return json({ error: "unauthorized" }, 401);
      if (!provider) return json({ skipped: "provider_not_configured" });
      const since = new Date(Date.now() - 3 * 86400_000).toISOString();
      const before = new Date(Date.now() - 5 * 60_000).toISOString();
      const { data } = await db.from("payments").select(COLUMNS).eq("status", "pending")
        .gte("created_at", since).lte("created_at", before).limit(100);
      const results: Record<string, number> = {};
      for (const p of (data ?? []) as PaymentRow[]) {
        const s = await syncPayment(db, provider, p, "check");
        results[s] = (results[s] ?? 0) + 1;
      }
      // Paiements abandonnés depuis plus de 3 jours : annulés (aucun droit accordé).
      await db.from("payments").update({ status: "cancelled", provider_status: "ABANDONNE" })
        .eq("status", "pending").lt("created_at", since);
      return json({ checked: data?.length ?? 0, results });
    }

    const caller = await callerFrom(req, ctx);
    if (!caller) return json({ error: "unauthorized" }, 401);
    const { data: flag } = await db.from("feature_flags").select("enabled").eq("key", "payments").maybeSingle();
    if (!flag?.enabled) return json({ error: "feature_disabled" }, 403);

    if (action === "status") {
      const { data: p } = await db.from("payments").select(COLUMNS).eq("id", String(body?.payment_id ?? ""))
        .eq("user_id", caller.id).maybeSingle();
      if (!p) return json({ error: "payment_not_found" }, 404);
      const state = provider ? await syncPayment(db, provider, p as PaymentRow, "return") : (p as PaymentRow).status;
      const { data: ent } = await db.rpc("svc_credit_summary", { p_user: caller.id });
      return json({ status: state, credits: ent });
    }

    if (action !== "checkout") return json({ error: "unknown_action", allowed: ["checkout", "status"] }, 400);
    if (!provider) return json({ error: "provider_not_configured" }, 503);

    const settings = await readSettings(db, [
      "pricing.plans",
      "pricing.credit_pack",
      "pricing.annual_discount_percent",
      "pricing.credit_pack_max_quantity",
      "payments.channels",
    ]);
    const product = String(body?.product ?? "");
    let row: Record<string, unknown>;
    let description: string;
    if (product === "subscription") {
      const plans = (settings["pricing.plans"] ?? []) as PlanSetting[];
      const period = body?.period === "annual" ? "annual" : "monthly";
      const code = String(body?.plan_code ?? "");
      const amount = subscriptionPrice(plans, code, period, Number(settings["pricing.annual_discount_percent"] ?? 0));
      if (!amount) return json({ error: "invalid_plan" }, 400);
      const name = plans.find((p) => p.code === code)?.name ?? code;
      row = { kind: "subscription", plan_code: code, period, amount_xof: amount };
      description = `Coupon Pro IA - forfait ${name} ${period === "annual" ? "12 mois" : "1 mois"}`;
    } else if (product === "credits") {
      const max = Number(settings["pricing.credit_pack_max_quantity"] ?? 5);
      const quantity = Math.round(Number(body?.quantity ?? 1));
      if (!(quantity >= 1 && quantity <= max)) return json({ error: "invalid_quantity", max }, 400);
      const { credits, amount } = creditsPrice(settings["pricing.credit_pack"] as { credits: number; price_xof: number }, quantity);
      row = { kind: "credits", credits, amount_xof: amount };
      description = `Coupon Pro IA - ${credits} credits IA`;
    } else {
      return json({ error: "invalid_product" }, 400);
    }

    // Code promo : contrôlé et appliqué ici (le prix affiché par l'app n'est qu'indicatif).
    const promoInput = String(body?.promo_code ?? "").trim();
    if (promoInput) {
      const { data: promo, error: promoError } = await db.rpc("svc_promo_check", {
        p_user: caller.id,
        p_code: promoInput,
        p_kind: row.kind,
        p_plan: (row.plan_code as string | undefined) ?? null,
      });
      if (promoError) throw new Error(promoError.message);
      if (!promo?.ok) return json({ error: "invalid_promo", reason: promo?.reason ?? "unknown" }, 400);
      const { amount, discount } = applyPromo(row.amount_xof as number, Number(promo.percent_off));
      row = { ...row, amount_xof: amount, discount_xof: discount, promo_code: promo.code };
      description += ` (code ${promo.code})`;
    }

    // Anti-abus : pas plus de 5 paiements en attente à la fois.
    const { count } = await db.from("payments").select("id", { count: "exact", head: true })
      .eq("user_id", caller.id).eq("status", "pending");
    if ((count ?? 0) >= 5) return json({ error: "too_many_pending" }, 429);

    const transactionId = newTransactionId();
    const { data: payment, error } = await db.from("payments").insert({
      ...row,
      user_id: caller.id,
      provider: provider.name,
      transaction_id: transactionId,
      currency: "XOF",
    }).select("id").single();
    if (error) throw new Error(error.message);

    try {
      const out = await provider.checkout({
        transactionId,
        amountXof: row.amount_xof as number,
        description,
        notifyUrl: `${url}/functions/v1/payment-webhook`,
        returnUrl: `${url}/functions/v1/payment-return`,
        customerId: caller.id,
        channels: String(settings["payments.channels"] ?? "MOBILE_MONEY"),
      });
      await db.from("payments").update({ payment_url: out.paymentUrl, provider_payload: out.raw as Record<string, unknown> })
        .eq("id", payment.id);
      return json({ payment_id: payment.id, payment_url: out.paymentUrl, amount_xof: row.amount_xof, discount_xof: row.discount_xof ?? 0 });
    } catch (e) {
      await db.from("payments").update({
        status: "failed",
        provider_status: e instanceof PaymentProviderError ? `${e.code} ${e.message}` : String(e),
      }).eq("id", payment.id);
      return json({ error: "provider_error", message: e instanceof Error ? e.message : String(e) }, 502);
    }
  } catch (e) {
    console.error("payments", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
