import { assert, assertEquals } from "jsr:@std/assert@1";
import { fcmPayload, parseServiceAccount, sendToToken, signedAssertion } from "./fcm.ts";

async function testAccount() {
  const keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey));
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  return {
    keys,
    raw: JSON.stringify({ project_id: "demo", client_email: "x@demo.iam.gserviceaccount.com", private_key: pem }),
  };
}

Deno.test("compte de service : lecture et refus des valeurs incomplètes", () => {
  assertEquals(parseServiceAccount(undefined), null);
  assertEquals(parseServiceAccount("pas du json"), null);
  assertEquals(parseServiceAccount(JSON.stringify({ project_id: "p" })), null);
});

Deno.test("JWT signé RS256, vérifiable avec la clé publique", async () => {
  const { keys, raw } = await testAccount();
  const sa = parseServiceAccount(raw)!;
  const jwt = await signedAssertion(sa, 1_000_000);
  const [h, c, s] = jwt.split(".");
  const dec = (x: string) => Uint8Array.from(atob(x.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((x.length + 3) % 4)), (ch) => ch.charCodeAt(0));
  const claims = JSON.parse(new TextDecoder().decode(dec(c)));
  assertEquals(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(claims.exp - claims.iat, 3600);
  assert(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", keys.publicKey, dec(s), new TextEncoder().encode(`${h}.${c}`)));
});

Deno.test("message FCM : titre, texte, lien et canal Android", () => {
  const p = fcmPayload("tok", { id: 7, kind: "coupon", title: "T", body: "B", route: "/coupon/x" });
  assertEquals(p.message.notification, { title: "T", body: "B" });
  assertEquals(p.message.data.route, "/coupon/x");
  assertEquals(p.message.android.notification.channel_id, "coupon_pro_ia");
});

Deno.test("jeton désinscrit détecté (supprimé ensuite)", async () => {
  const fake = (status: number, body: string) => () => Promise.resolve(new Response(body, { status }));
  const gone = await sendToToken("p", "b", "t", { id: 1, kind: "system", title: "a", body: "b" }, fake(404, '{"error":{"status":"NOT_FOUND"}}') as typeof fetch);
  assertEquals(gone.ok, false);
  assert(!gone.ok && gone.unregistered);
  const ok = await sendToToken("p", "b", "t", { id: 1, kind: "system", title: "a", body: "b" }, fake(200, "{}") as typeof fetch);
  assertEquals(ok.ok, true);
  const busy = await sendToToken("p", "b", "t", { id: 1, kind: "system", title: "a", body: "b" }, fake(503, "busy") as typeof fetch);
  assert(!busy.ok && !busy.unregistered);
});
