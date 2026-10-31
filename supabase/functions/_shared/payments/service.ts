// Logique commune des paiements : relire le statut chez l'agrégateur, contrôler le montant,
// enregistrer, puis exécuter (abonnement ou crédits) une seule fois.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { CinetPayProvider, LigdiCashProvider, PAYMENT_PROVIDERS, type PaymentProvider } from "./provider.ts";

/** Agrégateurs dont les clés sont configurées (secrets du serveur), par nom. */
export function providersFromEnv(env: (k: string) => string | undefined, storeUrl = ""): Map<string, PaymentProvider> {
  const out = new Map<string, PaymentProvider>();
  const ligKey = env("LIGDICASH_API_KEY");
  const ligToken = env("LIGDICASH_API_TOKEN");
  if (ligKey && ligToken) out.set("ligdicash", new LigdiCashProvider(ligKey, ligToken, storeUrl));
  const key = env("CINETPAY_API_KEY");
  const site = env("CINETPAY_SITE_ID");
  if (key && site) out.set("cinetpay", new CinetPayProvider(key, site));
  return out;
}

/**
 * Agrégateurs à essayer pour un nouveau paiement : ordre du réglage « payments.providers »
 * (choisi dans la console), limité à ceux dont les clés sont configurées.
 */
export function orderedProviders(configured: Map<string, PaymentProvider>, setting: unknown): PaymentProvider[] {
  const wanted = Array.isArray(setting) && setting.length
    ? setting.map(String).filter((n) => (PAYMENT_PROVIDERS as readonly string[]).includes(n))
    : [...PAYMENT_PROVIDERS];
  return [...new Set(wanted)].map((n) => configured.get(n)).filter((p): p is PaymentProvider => Boolean(p));
}

export interface PaymentRow {
  id: string;
  user_id: string;
  transaction_id: string;
  provider: string;
  provider_ref: string | null;
  amount_xof: number;
  currency: string;
  status: string;
  fulfilled_at: string | null;
}

/** Relit le paiement chez SON agrégateur ; met à jour et exécute si confirmé. Idempotent. */
export async function syncPayment(
  db: SupabaseClient,
  providers: Map<string, PaymentProvider>,
  p: PaymentRow,
  source: "webhook" | "check" | "return",
) {
  if (p.status === "succeeded") {
    if (!p.fulfilled_at) await db.rpc("svc_fulfill_payment", { p_payment: p.id });
    return "succeeded";
  }
  if (p.status !== "pending") return p.status;
  const provider = providers.get(p.provider);
  if (!provider) return "pending"; // clés retirées : on réessaiera plus tard
  const r = await provider.check({ transactionId: p.transaction_id, providerRef: p.provider_ref });
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
