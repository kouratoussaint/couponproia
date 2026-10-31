// Tests des paiements : `deno test supabase/functions/_shared`
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  applyPromo,
  CinetPayProvider,
  creditsPrice,
  interpretCinetPayCheck,
  newTransactionId,
  PaymentProviderError,
  subscriptionPrice,
  verifyCinetPayToken,
} from "./provider.ts";
import {
  interpretLigdiCashConfirm,
  LigdiCashProvider,
  ligdiCashTransactionId,
} from "./provider.ts";
import { orderedProviders, providersFromEnv } from "./service.ts";

const PLANS = [
  { code: "FREE", name: "FREE", monthly_xof: 0, ai_credits: 2 },
  { code: "STARTER", name: "STARTER", monthly_xof: 2000, ai_credits: 10 },
];

Deno.test("prix calculés côté serveur : mensuel, annuel, packs ; FREE non vendable", () => {
  assertEquals(subscriptionPrice(PLANS, "STARTER", "monthly", 15), 2000);
  assertEquals(subscriptionPrice(PLANS, "STARTER", "annual", 15), 20400);
  assertEquals(subscriptionPrice(PLANS, "FREE", "monthly", 0), null);
  assertEquals(subscriptionPrice(PLANS, "INCONNU", "monthly", 0), null);
  assertEquals(creditsPrice({ credits: 10, price_xof: 500 }, 3), { credits: 30, amount: 1500 });
});

Deno.test("vérification CinetPay : accepté, refusé, en attente", () => {
  assertEquals(interpretCinetPayCheck({ code: "00", message: "SUCCES", data: { status: "ACCEPTED", amount: "2000", currency: "XOF" } }).state, "succeeded");
  assertEquals(interpretCinetPayCheck({ code: "627", message: "TRANSACTION_CANCEL", data: { status: "REFUSED" } }).state, "failed");
  assertEquals(interpretCinetPayCheck({ code: "662", message: "WAITING_CUSTOMER_PAYMENT", data: { status: "WAITING_CUSTOMER_PAYMENT" } }).state, "pending");
  assertEquals(interpretCinetPayCheck(null).state, "pending");
  assertEquals(interpretCinetPayCheck({ code: "00", data: { status: "ACCEPTED", amount: "2000" } }).amount, 2000);
});

Deno.test("initialisation : URL de paiement, erreur explicite sinon", async () => {
  let sent: Record<string, unknown> = {};
  const ok = new CinetPayProvider("k", "s", ((_u: string, init: RequestInit) => {
    sent = JSON.parse(String(init.body));
    return Promise.resolve(Response.json({ code: "201", message: "CREATED", data: { payment_url: "https://checkout.cinetpay.com/x" } }));
  }) as typeof fetch);
  const r = await ok.checkout({ transactionId: "T1", amountXof: 2000, description: "d", notifyUrl: "n", returnUrl: "r", customerId: "u", channels: "MOBILE_MONEY" });
  assertEquals(r.paymentUrl, "https://checkout.cinetpay.com/x");
  assertEquals([sent.currency, sent.amount, sent.site_id], ["XOF", 2000, "s"]);
  const ko = new CinetPayProvider("k", "s", (() => Promise.resolve(Response.json({ code: "608", message: "MINIMUM_REQUIRED_FIELDS" }))) as unknown as typeof fetch);
  await assertRejects(() => ko.checkout({ transactionId: "T", amountXof: 5, description: "", notifyUrl: "", returnUrl: "", customerId: "", channels: "" }), PaymentProviderError);
});

Deno.test("jeton x-token : HMAC-SHA256 des champs, faux jeton refusé", async () => {
  const form = { cpm_site_id: "123", cpm_trans_id: "T1", cpm_amount: "2000", cpm_currency: "XOF" };
  const data = "123T12000XOF";
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("secret"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const hex = [...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  assert(await verifyCinetPayToken(form, hex, "secret"));
  assert(!(await verifyCinetPayToken(form, hex.replace(/^./, "0") === hex ? hex.replace(/^./, "1") : hex.replace(/^./, "0"), "secret")));
  assert(!(await verifyCinetPayToken(form, null, "secret")));
});

Deno.test("références de transaction uniques et alphanumériques", () => {
  const a = newTransactionId(1);
  const b = newTransactionId(1);
  assert(/^[A-Z0-9]+$/.test(a) && a.length <= 30);
  assert(a !== b);
});

Deno.test("code promo : réduction arrondie au multiple de 5, reste à payer positif", () => {
  assertEquals(applyPromo(2000, 20), { amount: 1600, discount: 400 });
  assertEquals(applyPromo(20400, 15), { amount: 17340, discount: 3060 });
  assertEquals(applyPromo(505, 33), { amount: 340, discount: 165 });
  assertEquals(applyPromo(2000, 150), { amount: 200, discount: 1800 });
  for (const [a, p] of [[2000, 7], [5000, 13], [495, 89], [10000, 1]]) {
    const r = applyPromo(a, p);
    assert(r.amount > 0 && r.amount % 5 === 0 && r.amount + r.discount === a);
  }
});

// ---------------------------------------------------------------------------
// LigdiCash
// ---------------------------------------------------------------------------

const ligCustom = (id: string) => [
  { keyof_customdata: "transaction_id", valueof_customdata: id, datecreation_customdata: "2026-10-31" },
  { keyof_customdata: "logfile", valueof_customdata: "x", datecreation_customdata: "2026-10-31" },
];

Deno.test("LigdiCash : facture créée avec le jeton, en-têtes Apikey et Bearer", async () => {
  let seen: { url: string; init: RequestInit } | null = null;
  const fake = ((url: string, init: RequestInit) => {
    seen = { url, init };
    return Promise.resolve(new Response(JSON.stringify({
      response_code: "00",
      token: "TOK123",
      response_text: "https://app.ligdicash.com/pay/invoice/TOK123",
    })));
  }) as unknown as typeof fetch;
  const p = new LigdiCashProvider("KEY", "SECRET", "https://exemple.test", fake);
  const out = await p.checkout({
    transactionId: "CPIABC",
    amountXof: 2000,
    description: "Coupon Pro IA - forfait STARTER 1 mois",
    notifyUrl: "https://x/functions/v1/payment-webhook?p=ligdicash",
    returnUrl: "https://x/functions/v1/payment-return",
    customerId: "u",
    channels: "MOBILE_MONEY",
  });
  assertEquals(out.providerRef, "TOK123");
  assertEquals(out.paymentUrl, "https://app.ligdicash.com/pay/invoice/TOK123");
  const s = seen as unknown as { url: string; init: RequestInit };
  const h = s.init.headers as Record<string, string>;
  assertEquals(h.Apikey, "KEY");
  assertEquals(h.Authorization, "Bearer SECRET");
  const body = JSON.parse(String(s.init.body));
  assertEquals(body.commande.invoice.total_amount, 2000);
  assertEquals(body.commande.invoice.devise, "XOF");
  assertEquals(body.commande.invoice.customer, "");
  assertEquals(body.commande.custom_data.transaction_id, "CPIABC");
  const refused = new LigdiCashProvider("KEY", "SECRET", "https://exemple.test", (() =>
    Promise.resolve(new Response(JSON.stringify({ response_code: "01", token: "", response_text: "Echec (Code00)" })))) as unknown as typeof fetch);
  await assertRejects(() => refused.checkout({
    transactionId: "CPIABD", amountXof: 2000, description: "d", notifyUrl: "n", returnUrl: "r", customerId: "u", channels: "",
  }), PaymentProviderError);
});

Deno.test("LigdiCash : statut relu, transaction vérifiée, numéro masqué", () => {
  const ok = interpretLigdiCashConfirm({
    response_code: "00", status: "completed", amount: 2000, montant: 2000, operator_name: "ORANGE BF",
    customer: "22670000000", custom_data: ligCustom("CPIABC"), external_id: "CPIABC",
  }, "CPIABC");
  assertEquals(ok.state, "succeeded");
  assertEquals(ok.amount, 2000);
  assertEquals(ok.currency, "XOF");
  assertEquals(ok.paymentMethod, "ORANGE BF");
  assert(!JSON.stringify(ok.raw).includes("22670000000"), "numéro masqué");
  assertEquals(interpretLigdiCashConfirm({ response_code: "00", status: "pending", custom_data: ligCustom("CPIABC") }, "CPIABC").state, "pending");
  assertEquals(interpretLigdiCashConfirm({ response_code: "00", status: "notcompleted", custom_data: ligCustom("CPIABC") }, "CPIABC").state, "failed");
  assertEquals(interpretLigdiCashConfirm({ response_code: "01", response_text: "Echec (Code01)", status: "" }, "CPIABC").state, "pending");
  const other = interpretLigdiCashConfirm({ response_code: "00", status: "completed", amount: 2000, custom_data: ligCustom("CPIAUTRE") }, "CPIABC");
  assertEquals(other.state, "failed", "jeton d'une autre transaction refusé");
});

Deno.test("LigdiCash : référence lue dans la notification JSON ou formulaire", () => {
  assertEquals(ligdiCashTransactionId({ custom_data: ligCustom("CPIJSON") }), "CPIJSON");
  assertEquals(ligdiCashTransactionId({
    "custom_data[0][keyof_customdata]": "logfile",
    "custom_data[0][valueof_customdata]": "x",
    "custom_data[1][keyof_customdata]": "transaction_id",
    "custom_data[1][valueof_customdata]": "CPIFORM",
  }), "CPIFORM");
  assertEquals(ligdiCashTransactionId({ external_id: "123;CPIEXT" }), "CPIEXT");
  assertEquals(ligdiCashTransactionId({}), null);
});

Deno.test("ordre des agrégateurs : réglage de la console, limité aux clés présentes", () => {
  const env = (all: Record<string, string>) => (k: string) => all[k];
  const both = providersFromEnv(env({ LIGDICASH_API_KEY: "a", LIGDICASH_API_TOKEN: "b", CINETPAY_API_KEY: "c", CINETPAY_SITE_ID: "d" }));
  assertEquals(orderedProviders(both, null).map((p) => p.name), ["ligdicash", "cinetpay"]);
  assertEquals(orderedProviders(both, ["cinetpay", "ligdicash"]).map((p) => p.name), ["cinetpay", "ligdicash"]);
  assertEquals(orderedProviders(both, ["cinetpay"]).map((p) => p.name), ["cinetpay"]);
  const onlyCinet = providersFromEnv(env({ CINETPAY_API_KEY: "c", CINETPAY_SITE_ID: "d" }));
  assertEquals(orderedProviders(onlyCinet, ["ligdicash", "cinetpay"]).map((p) => p.name), ["cinetpay"]);
  assertEquals(orderedProviders(providersFromEnv(env({})), null).length, 0);
});
