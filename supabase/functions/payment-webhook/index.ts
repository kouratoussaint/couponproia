// Edge Function : notification de paiement de l'agrégateur (CinetPay).
// La notification ne fait que déclencher une vérification : le statut réel et le montant sont
// relus auprès de l'agrégateur avant tout droit accordé. Réponse 200 dans tous les cas traités.
import { env, serverContext } from "../_shared/http.ts";
import { verifyCinetPayToken } from "../_shared/payments/provider.ts";
import { type PaymentRow, providerFromEnv, syncPayment } from "../_shared/payments/service.ts";

Deno.serve(async (req) => {
  // CinetPay teste l'URL en GET : elle doit répondre 200.
  if (req.method !== "POST") return new Response("ok", { status: 200 });
  const ctx = serverContext();
  const provider = providerFromEnv((k) => env(k));
  if (!ctx || !provider) return new Response("not configured", { status: 503 });
  const { db } = ctx;

  let form: Record<string, string> = {};
  const type = req.headers.get("content-type") ?? "";
  try {
    if (type.includes("application/json")) form = await req.json();
    else form = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
  } catch {
    return new Response("bad request", { status: 400 });
  }
  const transactionId = String(form.cpm_trans_id ?? "");
  if (!transactionId) return new Response("missing cpm_trans_id", { status: 400 });

  const validToken = await verifyCinetPayToken(form, req.headers.get("x-token"), env("CINETPAY_SECRET_KEY") ?? "");
  const { data: payment } = await db.from("payments")
    .select("id, user_id, transaction_id, amount_xof, currency, status, fulfilled_at")
    .eq("transaction_id", transactionId).maybeSingle();
  await db.from("payment_events").insert({
    payment_id: payment?.id ?? null,
    source: "webhook",
    valid_token: validToken,
    payload: { ...form, cel_phone_num: form.cel_phone_num ? "masqué" : undefined },
  });
  if (!payment) return new Response("unknown transaction", { status: 200 });
  try {
    await syncPayment(db, provider, payment as PaymentRow, "webhook");
  } catch (e) {
    console.error("payment-webhook", e);
    return new Response("retry", { status: 500 });
  }
  return new Response("ok", { status: 200 });
});
