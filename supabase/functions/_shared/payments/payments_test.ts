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
