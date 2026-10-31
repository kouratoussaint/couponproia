// Edge Function : notifications de paiement des agrégateurs (LigdiCash, CinetPay).
// La notification ne fait que déclencher une vérification : le statut réel et le montant sont
// relus auprès de l'agrégateur du paiement avant tout droit accordé. Réponse 200 dans tous les
// cas traités (LigdiCash envoie deux notifications identiques : JSON puis formulaire).
import { env, serverContext } from "../_shared/http.ts";
import { ligdiCashTransactionId, verifyCinetPayToken } from "../_shared/payments/provider.ts";
import { type PaymentRow, providersFromEnv, syncPayment } from "../_shared/payments/service.ts";

Deno.serve(async (req) => {
  // CinetPay teste l'URL en GET : elle doit répondre 200.
  if (req.method !== "POST") return new Response("ok", { status: 200 });
  const ctx = serverContext();
  if (!ctx) return new Response("not configured", { status: 503 });
  const { db, url } = ctx;
  const providers = providersFromEnv((k) => env(k), `${url}/functions/v1/payment-return`);
  if (providers.size === 0) return new Response("not configured", { status: 503 });
  const source = new URL(req.url).searchParams.get("p") === "ligdicash" ? "ligdicash" : "cinetpay";

  let form: Record<string, unknown> = {};
  const type = req.headers.get("content-type") ?? "";
  try {
    if (type.includes("application/json")) form = await req.json();
    else form = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
  } catch {
    return new Response("bad request", { status: 400 });
  }

  let transactionId = "";
  let validToken: boolean | null = null;
  let logged: Record<string, unknown>;
  if (source === "ligdicash") {
    transactionId = ligdiCashTransactionId(form) ?? "";
    // Aucune signature chez LigdiCash : seuls le statut et le montant relus font foi.
    logged = { status: form.status, response_code: form.response_code, transaction_id: transactionId, amount: form.amount };
  } else {
    transactionId = String(form.cpm_trans_id ?? "");
    validToken = await verifyCinetPayToken(form as Record<string, string>, req.headers.get("x-token"), env("CINETPAY_SECRET_KEY") ?? "");
    logged = { ...form, cel_phone_num: form.cel_phone_num ? "masqué" : undefined };
  }
  if (!transactionId) return new Response("missing transaction id", { status: 400 });

  const { data: payment } = await db.from("payments")
    .select("id, user_id, transaction_id, provider, provider_ref, amount_xof, currency, status, fulfilled_at")
    .eq("transaction_id", transactionId).eq("provider", source).maybeSingle();
  await db.from("payment_events").insert({
    payment_id: payment?.id ?? null,
    source: "webhook",
    valid_token: validToken,
    payload: { provider: source, ...logged },
  });
  if (!payment) return new Response("unknown transaction", { status: 200 });
  try {
    await syncPayment(db, providers, payment as PaymentRow, "webhook");
  } catch (e) {
    console.error("payment-webhook", e);
    return new Response("retry", { status: 500 });
  }
  return new Response("ok", { status: 200 });
});
