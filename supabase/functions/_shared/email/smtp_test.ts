import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { buildMessage, type Channel, converse, encodeHeader, smtpFromEnv } from "./smtp.ts";

function fakeServer(replies: string[]): Channel & { sent: string[] } {
  const queue = [...replies];
  const sent: string[] = [];
  return {
    sent,
    read: () => Promise.resolve(queue.shift() ?? null),
    write: (l: string) => {
      sent.push(l);
      return Promise.resolve();
    },
    close: () => {},
  };
}

const cfg = { host: "h", port: 465, user: "u", pass: "p" };
const mail = { from: "ops@exemple.com", to: ["a@exemple.com"], subject: "Génération en échec", text: "Corps é" };

Deno.test("SMTP : dialogue complet, réponses sur plusieurs lignes", async () => {
  const ch = fakeServer(["220 ok", "250-hello", "250 AUTH LOGIN", "334 VXNlcm5hbWU6", "334 UGFzc3dvcmQ6", "235 ok",
    "250 ok", "250 ok", "354 go", "250 queued"]);
  await converse(ch, cfg, mail);
  assertEquals(ch.sent[0], "EHLO couponproia\r\n");
  assertEquals(ch.sent[2], btoa("u") + "\r\n");
  assert(ch.sent.some((l) => l.startsWith("RCPT TO:<a@exemple.com>")));
  assert(ch.sent.at(-1) === "QUIT\r\n");
});

Deno.test("SMTP : authentification refusée", async () => {
  const ch = fakeServer(["220 ok", "250 ok", "334 x", "334 y", "535 bad credentials"]);
  await assertRejects(() => converse(ch, cfg, mail), Error, "535");
});

Deno.test("message : en-têtes encodés, corps en base64", () => {
  const m = buildMessage(mail, new Date("2026-11-01T12:00:00Z"), "id");
  assert(m.includes("Subject: =?UTF-8?B?"));
  assert(m.includes("Content-Transfer-Encoding: base64"));
  assertEquals(encodeHeader("simple"), "simple");
});

Deno.test("configuration : port 465 et Brevo par défaut", () => {
  const env: Record<string, string> = { SMTP_USER: "u", SMTP_PASS: "p", SMTP_SENDER_EMAIL: "f@x.com" };
  const c = smtpFromEnv((k) => env[k]);
  assertEquals(c?.port, 465);
  assertEquals(c?.host, "smtp-relay.brevo.com");
  assertEquals(smtpFromEnv(() => undefined), null);
});
