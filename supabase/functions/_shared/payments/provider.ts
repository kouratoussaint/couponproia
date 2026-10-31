// Interface de paiement (PaymentProvider) et adaptateur CinetPay.
// Règle : une notification n'est jamais crue sur parole ; le statut réel est toujours relu
// auprès de l'agrégateur (API de vérification), puis comparé au montant attendu.

export type FetchFn = typeof fetch;

export interface CheckoutRequest {
  transactionId: string;
  amountXof: number;
  description: string;
  notifyUrl: string;
  returnUrl: string;
  customerId: string;
  channels: string;
}

export interface CheckoutResult {
  paymentUrl: string;
  raw: unknown;
}

export type PaymentState = "succeeded" | "failed" | "pending";

export interface CheckResult {
  state: PaymentState;
  providerStatus: string;
  amount: number | null;
  currency: string | null;
  paymentMethod: string | null;
  paidAt: string | null;
  raw: unknown;
}

export interface PaymentProvider {
  readonly name: string;
  checkout(req: CheckoutRequest): Promise<CheckoutResult>;
  check(transactionId: string): Promise<CheckResult>;
}

export class PaymentProviderError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

const BASE = "https://api-checkout.cinetpay.com/v2";

export class CinetPayProvider implements PaymentProvider {
  readonly name = "cinetpay";

  constructor(
    private readonly apiKey: string,
    private readonly siteId: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  async checkout(req: CheckoutRequest): Promise<CheckoutResult> {
    const res = await this.fetchFn(`${BASE}/payment`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        apikey: this.apiKey,
        site_id: this.siteId,
        transaction_id: req.transactionId,
        amount: req.amountXof,
        currency: "XOF",
        description: req.description,
        notify_url: req.notifyUrl,
        return_url: req.returnUrl,
        channels: req.channels,
        lang: "fr",
        customer_id: req.customerId,
        metadata: req.transactionId,
      }),
    });
    const body = await res.json().catch(() => ({}));
    const url = body?.data?.payment_url;
    if (String(body?.code) !== "201" || typeof url !== "string") {
      throw new PaymentProviderError(String(body?.code ?? res.status), String(body?.message ?? body?.description ?? "initialisation refusée"));
    }
    return { paymentUrl: url, raw: body };
  }

  async check(transactionId: string): Promise<CheckResult> {
    const res = await this.fetchFn(`${BASE}/payment/check`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ apikey: this.apiKey, site_id: this.siteId, transaction_id: transactionId }),
    });
    const body = await res.json().catch(() => ({}));
    return interpretCinetPayCheck(body);
  }
}

/** Traduit la réponse de vérification CinetPay en état interne. */
export function interpretCinetPayCheck(body: Record<string, unknown> | null): CheckResult {
  // deno-lint-ignore no-explicit-any
  const b = (body ?? {}) as any;
  const status = String(b?.data?.status ?? b?.message ?? "INCONNU").toUpperCase();
  const code = String(b?.code ?? "");
  let state: PaymentState = "pending";
  if (code === "00" && status === "ACCEPTED") state = "succeeded";
  else if (["REFUSED", "CANCELED", "CANCELLED", "TRANSACTION_CANCEL", "PAYMENT_FAILED"].includes(status) || ["600", "627"].includes(code)) {
    state = "failed";
  }
  const amount = Number(b?.data?.amount);
  return {
    state,
    providerStatus: status,
    amount: Number.isFinite(amount) ? amount : null,
    currency: b?.data?.currency ?? null,
    paymentMethod: b?.data?.payment_method ?? null,
    paidAt: typeof b?.data?.payment_date === "string" && b.data.payment_date.trim() ? b.data.payment_date : null,
    raw: b,
  };
}

/** Champs de la notification CinetPay concaténés pour le jeton HMAC (ordre de la documentation). */
const TOKEN_FIELDS = [
  "cpm_site_id", "cpm_trans_id", "cpm_trans_date", "cpm_amount", "cpm_currency", "signature", "payment_method",
  "cel_phone_num", "cpm_phone_prefixe", "cpm_language", "cpm_version", "cpm_payment_config", "cpm_page_action",
  "cpm_custom", "cpm_designation", "cpm_error_message",
];

/** Vérifie l'en-tête x-token (HMAC-SHA256 avec la clé secrète). Indicatif : le statut est toujours relu. */
export async function verifyCinetPayToken(form: Record<string, string>, token: string | null, secret: string): Promise<boolean> {
  if (!token || !secret) return false;
  const data = TOKEN_FIELDS.map((f) => form[f] ?? "").join("");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data)));
  const hex = [...sig].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (hex.length !== token.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ token.toLowerCase().charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Prix (calculés côté serveur à partir des réglages, jamais envoyés par l'app)
// ---------------------------------------------------------------------------
export interface PlanSetting {
  code: string;
  name: string;
  monthly_xof: number;
  ai_credits: number;
}

export function subscriptionPrice(plans: PlanSetting[], code: string, period: "monthly" | "annual", annualDiscountPercent: number): number | null {
  const plan = plans.find((p) => p.code === code);
  if (!plan || !(plan.monthly_xof > 0)) return null;
  if (period === "monthly") return Math.round(plan.monthly_xof / 5) * 5;
  const raw = plan.monthly_xof * 12 * (1 - Math.min(90, Math.max(0, annualDiscountPercent)) / 100);
  return Math.round(raw / 100) * 100;
}

export function creditsPrice(pack: { credits: number; price_xof: number }, quantity: number): { credits: number; amount: number } {
  return { credits: pack.credits * quantity, amount: Math.round((pack.price_xof * quantity) / 5) * 5 };
}

/** Réduction d'un code promo : arrondie au multiple de 5 inférieur, le reste à payer reste positif. */
export function applyPromo(amount: number, percentOff: number): { amount: number; discount: number } {
  const pct = Math.min(90, Math.max(0, Math.floor(percentOff)));
  const discount = Math.floor((amount * pct) / 100 / 5) * 5;
  return { amount: amount - discount, discount };
}

/** Référence unique acceptée par l'agrégateur (lettres et chiffres). */
export function newTransactionId(now = Date.now()): string {
  const rand = crypto.getRandomValues(new Uint8Array(5));
  return `CPI${now.toString(36).toUpperCase()}${[...rand].map((b) => b.toString(36).padStart(2, "0")).join("").toUpperCase()}`;
}
