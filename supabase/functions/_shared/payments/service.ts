// Logique commune des paiements : relire le statut chez l'agrégateur, contrôler le montant,
// enregistrer, puis exécuter (abonnement ou crédits) une seule fois.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { CinetPayProvider, type PaymentProvider } from "./provider.ts";

export function providerFromEnv(env: (k: string) => string | undefined): PaymentProvider | null {
  const key = env("CINETPAY_API_KEY");
  const site = env("CINETPAY_SITE_ID");
  return key && site ? new CinetPayProvider(key, site) : null;
}

export interface PaymentRow {
  id: string;
  user_id: string;
  transaction_id: string;
  amount_xof: number;
  currency: string;
  status: string;
  fulfilled_at: string | null;
}

/** Relit le paiement chez l'agrégateur ; met à jour et exécute si confirmé. Idempotent. */
export async function syncPayment(db: SupabaseClient, provider: PaymentProvider, p: PaymentRow, source: "webhook" | "check" | "return") {
  if (p.status === "succeeded") {
    if (!p.fulfilled_at) await db.rpc("svc_fulfill_payment", { p_payment: p.id });
    return "succeeded";
  }
  if (p.status !== "pending") return p.status;
  const r = await provider.check(p.transaction_id);
  await db.from("payment_events").insert({ payment_id: p.id, source, payload: r.raw as Record<string, unknown> });
  let state = r.state;
  let providerStatus = r.providerStatus;
  // Le montant et la devise confirmés doivent correspondre exactement à ce qui était dû.
  if (state === "succeeded" && (r.amount !== p.amount_xof || (r.currency ?? "XOF") !== p.currency)) {
    state = "failed";
    providerStatus = `MONTANT_INCOHERENT (${r.amount} ${r.currency})`;
  }
  if (state === "pending") {
    await db.from("payments").update({ provider_status: providerStatus }).eq("id", p.id);
    return "pending";
  }
  const { data: updated } = await db.from("payments").update({
    status: state,
    provider_status: providerStatus,
    payment_method: r.paymentMethod,
    provider_payload: r.raw as Record<string, unknown>,
    paid_at: state === "succeeded" ? new Date().toISOString() : null,
  }).eq("id", p.id).eq("status", "pending").select("id").maybeSingle();
  if (state === "succeeded" && updated) {
    const { error } = await db.rpc("svc_fulfill_payment", { p_payment: p.id });
    if (error) throw new Error(`Exécution du paiement : ${error.message}`);
  }
  return state;
}
