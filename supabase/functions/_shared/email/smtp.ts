// Envoi d'e-mails par SMTP (TLS implicite, port 465 : les ports 25 et 587 sont fermés en sortie
// des Edge Functions). Client minimal sans dépendance : EHLO, AUTH LOGIN, MAIL, RCPT, DATA.

export interface Mail {
  from: string;
  fromName?: string;
  to: string[];
  subject: string;
  text: string;
}

export interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  pass: string;
}

/** Canal minimal (connexion TLS réelle, ou faux canal dans les tests). */
export interface Channel {
  read(): Promise<string | null>;
  write(line: string): Promise<void>;
  close(): void;
}

const enc = new TextEncoder();
const b64 = (s: string) => {
  const bytes = enc.encode(s);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
};

/** En-tête encodé (RFC 2047) pour les accents. */
export const encodeHeader = (s: string) => /^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(s)}?=`;

/** Message complet : en-têtes et corps en base64 (UTF-8), lignes de 76 caractères. */
export function buildMessage(mail: Mail, date = new Date(), id: string = crypto.randomUUID()): string {
  const body = b64(mail.text).replace(/.{1,76}/g, "$&\r\n");
  const from = mail.fromName ? `${encodeHeader(mail.fromName)} <${mail.from}>` : mail.from;
  return [
    `From: ${from}`,
    `To: ${mail.to.join(", ")}`,
    `Subject: ${encodeHeader(mail.subject)}`,
    `Date: ${date.toUTCString()}`,
    `Message-ID: <${id}@${mail.from.split("@")[1] ?? "localhost"}>`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    body,
  ].join("\r\n");
}

/** Lit une réponse SMTP (éventuellement sur plusieurs lignes) et vérifie son code. */
async function expect(ch: Channel, codes: number[]): Promise<string> {
  let last = "";
  for (;;) {
    const line = await ch.read();
    if (line === null) throw new Error("Connexion SMTP fermée");
    last = line;
    if (/^\d{3} /.test(line) || /^\d{3}$/.test(line)) break;
  }
  const code = Number(last.slice(0, 3));
  if (!codes.includes(code)) throw new Error(`SMTP ${last.slice(0, 200)}`);
  return last;
}

/** Dialogue SMTP complet sur un canal déjà ouvert. */
export async function converse(ch: Channel, cfg: SmtpConfig, mail: Mail): Promise<void> {
  try {
    await expect(ch, [220]);
    await ch.write("EHLO couponproia\r\n");
    await expect(ch, [250]);
    await ch.write("AUTH LOGIN\r\n");
    await expect(ch, [334]);
    await ch.write(b64(cfg.user) + "\r\n");
    await expect(ch, [334]);
    await ch.write(b64(cfg.pass) + "\r\n");
    await expect(ch, [235]);
    await ch.write(`MAIL FROM:<${mail.from}>\r\n`);
    await expect(ch, [250]);
    for (const to of mail.to) {
      await ch.write(`RCPT TO:<${to}>\r\n`);
      await expect(ch, [250, 251]);
    }
    await ch.write("DATA\r\n");
    await expect(ch, [354]);
    await ch.write(buildMessage(mail) + "\r\n.\r\n");
    await expect(ch, [250]);
    await ch.write("QUIT\r\n");
  } finally {
    ch.close();
  }
}

/** Connexion TLS réelle. */
export async function tlsChannel(host: string, port: number): Promise<Channel> {
  const conn = await Deno.connectTls({ hostname: host, port });
  const dec = new TextDecoder();
  let buffer = "";
  const chunk = new Uint8Array(4096);
  return {
    async read() {
      for (;;) {
        const i = buffer.indexOf("\r\n");
        if (i >= 0) {
          const line = buffer.slice(0, i);
          buffer = buffer.slice(i + 2);
          return line;
        }
        const n = await conn.read(chunk);
        if (n === null) return null;
        buffer += dec.decode(chunk.subarray(0, n));
      }
    },
    async write(line: string) {
      const data = enc.encode(line);
      let off = 0;
      while (off < data.length) off += await conn.write(data.subarray(off));
    },
    close() {
      try {
        conn.close();
      } catch { /* déjà fermée */ }
    },
  };
}

/** Configuration depuis les secrets (SMTP_HOST, SMTP_USER, SMTP_PASS, SMTP_SENDER_EMAIL), ou null. */
export function smtpFromEnv(get: (k: string) => string | undefined): (SmtpConfig & { from: string }) | null {
  const user = get("SMTP_USER")?.trim();
  const pass = get("SMTP_PASS")?.trim();
  const from = get("SMTP_SENDER_EMAIL")?.trim();
  if (!user || !pass || !from) return null;
  return { host: get("SMTP_HOST")?.trim() || "smtp-relay.brevo.com", port: 465, user, pass, from };
}

export async function sendMail(cfg: SmtpConfig, mail: Mail, open = tlsChannel): Promise<void> {
  const ch = await open(cfg.host, cfg.port);
  await converse(ch, cfg, mail);
}
