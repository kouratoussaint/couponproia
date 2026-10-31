// Interface de paiement (PaymentProvider) et adaptateurs LigdiCash et CinetPay.
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
  /** Page à afficher si le client annule (LigdiCash) ; par défaut, la page de retour. */
  cancelUrl?: string;
  customer?: { firstname?: string; lastname?: string; email?: string };
}

export interface CheckoutResult {
  paymentUrl: string;
  /** Référence de l'agrégateur à conserver pour la vérification (jeton de facture LigdiCash). */
  providerRef: string | null;
  raw: unknown;
}

/** Ce qu'il faut pour relire un paiement chez son agrégateur. */
export interface PaymentRef {
  transactionId: string;
  providerRef: string | null;
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
  check(ref: PaymentRef): Promise<CheckResult>;
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
    return { paymentUrl: url, providerRef: null, raw: body };
  }

  async check(ref: PaymentRef): Promise<CheckResult> {
    const res = await this.fetchFn(`${BASE}/payment/check`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ apikey: this.apiKey, site_id: this.siteId, transaction_id: ref.transactionId }),
    });
    const body = await res.json().catch(() => ({}));
    return interpretCinetPayCheck(body);
  }
}

// ---------------------------------------------------------------------------
// LigdiCash (payin avec redirection) — https://developers.ligdicash.com
// Pas de signature sur les notifications : le statut est toujours relu avec « confirm »
// et le jeton de facture conservé à la création.
// ---------------------------------------------------------------------------
const LIGDICASH = "https://app.ligdicash.com/pay/v01/redirect/checkout-invoice";

export class LigdiCashProvider implements PaymentProvider {
  readonly name = "ligdicash";

  constructor(
    private readonly apiKey: string,
    private readonly apiToken: string,
    private readonly storeUrl: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  private headers(json: boolean): Record<string, string> {
    return {
      Apikey: this.apiKey,
      Authorization: `Bearer ${this.apiToken}`,
      Accept: "application/json",
      ...(json ? { "Content-Type": "application/json" } : {}),
    };
  }

  async checkout(req: CheckoutRequest): Promise<CheckoutResult> {
    const res = await this.fetchFn(`${LIGDICASH}/create`, {
      method: "POST",
      headers: this.headers(true),
      body: JSON.stringify({
        commande: {
          invoice: {
            items: [{ name: req.description.slice(0, 120), description: "", quantity: 1, unit_price: req.amountXof, total_price: req.amountXof }],
            total_amount: req.amountXof,
            devise: "XOF",
            description: req.description,
            customer: "",
            customer_firstname: req.customer?.firstname ?? "",
            customer_lastname: req.customer?.lastname ?? "",
            customer_email: req.customer?.email ?? "",
            external_id: "",
            otp: "",
          },
          store: { name: "Coupon Pro IA", website_url: this.storeUrl },
          actions: {
            cancel_url: req.cancelUrl ?? req.returnUrl,
            return_url: req.returnUrl,
            callback_url: req.notifyUrl,
          },
          custom_data: { transaction_id: req.transactionId },
        },
      }),
    });
    const body = await res.json().catch(() => ({}));
    const url = body?.response_text;
    const token = body?.token;
    if (String(body?.response_code) !== "00" || typeof url !== "string" || !/^https:\/\//.test(url) || !token) {
      throw new PaymentProviderError(String(body?.response_code ?? res.status), String(body?.response_text ?? "facture refusée"));
    }
    return { paymentUrl: url, providerRef: String(token), raw: { response_code: body.response_code, response_text: url } };
  }

  async check(ref: PaymentRef): Promise<CheckResult> {
    if (!ref.providerRef) {
      return { state: "pending", providerStatus: "JETON_ABSENT", amount: null, currency: null, paymentMethod: null, paidAt: null, raw: {} };
    }
    const res = await this.fetchFn(`${LIGDICASH}/confirm/?invoiceToken=${encodeURIComponent(ref.providerRef)}`, {
      method: "GET",
      headers: this.headers(false),
    });
    const body = await res.json().catch(() => ({}));
    return interpretLigdiCashConfirm(body, ref.transactionId);
  }
}

/** Valeur d'une clé de custom_data (tableau keyof_customdata / valueof_customdata). */
export function ligdiCashCustomData(body: unknown, key: string): string | null {
  // deno-lint-ignore no-explicit-any
  const list = (body as any)?.custom_data;
  if (!Array.isArray(list)) return null;
  const e = list.find((x: { keyof_customdata?: string }) => x?.keyof_customdata === key);
  const v = e?.valueof_customdata;
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

/**
 * Référence de transaction d'une notification LigdiCash, en JSON (custom_data en tableau) ou en
 * formulaire (custom_data[0][keyof_customdata]…) ; à défaut, external_id (valeurs « id » jointes).
 */
export function ligdiCashTransactionId(form: Record<string, unknown>): string | null {
  const fromJson = ligdiCashCustomData(form, "transaction_id");
  if (fromJson) return fromJson;
  for (const [k, v] of Object.entries(form)) {
    const m = /^custom_data\[(\d+)\]\[keyof_customdata\]$/.exec(k);
    if (m && v === "transaction_id") {
      const value = form[`custom_data[${m[1]}][valueof_customdata]`];
      if (typeof value === "string" && value.trim()) return value.trim();
    }
  }
  const ext = typeof form.external_id === "string" ? form.external_id : "";
  return ext.split(";").map((s) => s.trim()).find((s) => /^CPI[A-Z0-9]+$/.test(s)) ?? null;
}

/** Traduit la réponse « confirm » de LigdiCash. Une réponse d'une autre transaction est refusée. */
export function interpretLigdiCashConfirm(body: Record<string, unknown> | null, transactionId: string): CheckResult {
  // deno-lint-ignore no-explicit-any
  const b = (body ?? {}) as any;
  const status = String(b?.status ?? "").toLowerCase();
  const code = String(b?.response_code ?? "");
  let state: PaymentState = "pending";
  if (code === "00" && status === "completed") state = "succeeded";
  else if (code === "00" && status === "notcompleted") state = "failed";
  const echoed = ligdiCashCustomData(b, "transaction_id") ?? (typeof b?.external_id === "string" ? b.external_id : null);
  let providerStatus = code === "00" ? (status || "inconnu").toUpperCase() : `ERREUR ${b?.response_text ?? code}`;
  if (state === "succeeded" && echoed && !echoed.split(";").includes(transactionId)) {
    state = "failed";
    providerStatus = "TRANSACTION_INCOHERENTE";
  }
  const amount = Number(b?.amount ?? b?.montant);
  const phone = typeof b?.customer === "string" ? b.customer : null;
  return {
    state,
    providerStatus,
    amount: Number.isFinite(amount) && amount > 0 ? amount : null,
    currency: state === "pending" ? null : "XOF",
    paymentMethod: typeof b?.operator_name === "string" && b.operator_name ? b.operator_name : null,
    paidAt: typeof b?.date === "string" && b.date.trim() ? b.date : null,
    // Numéro du payeur masqué dans le journal.
    raw: { ...b, customer: phone ? `${phone.slice(0, 5)}…${phone.slice(-2)}` : phone, customer_details: undefined },
  };
}

/** Agrégateurs connus, dans l'ordre de priorité par défaut. */
export const PAYMENT_PROVIDERS = ["ligdicash", "cinetpay"] as const;

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
