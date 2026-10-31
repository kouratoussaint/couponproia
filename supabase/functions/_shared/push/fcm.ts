// Envoi Firebase Cloud Messaging (API HTTP v1) avec un compte de service Google.
// Le jeton d'accès OAuth est obtenu en signant un JWT (RS256) avec la clé privée du compte de
// service (secret FCM_SERVICE_ACCOUNT, jamais dans l'app).

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri: string;
}

export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  try {
    const j = JSON.parse(raw);
    if (!j.project_id || !j.client_email || !j.private_key) return null;
    return {
      project_id: j.project_id,
      client_email: j.client_email,
      private_key: j.private_key,
      token_uri: j.token_uri ?? "https://oauth2.googleapis.com/token",
    };
  } catch {
    return null;
  }
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** JWT signé demandant le droit d'envoyer des messages FCM. */
export async function signedAssertion(sa: ServiceAccount, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key.replace(/\\n/g, "\n")),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  return `${header}.${claims}.${b64url(signature)}`;
}

export async function accessToken(sa: ServiceAccount, fetcher: typeof fetch = fetch): Promise<string> {
  const res = await fetcher(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await signedAssertion(sa),
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) throw new Error(`OAuth Google refusé (${res.status})`);
  return body.access_token as string;
}

export interface PushMessage {
  title: string;
  body: string;
  route?: string | null;
  kind: string;
  id: number;
}

export function fcmPayload(token: string, m: PushMessage) {
  return {
    message: {
      token,
      notification: { title: m.title, body: m.body },
      data: { route: m.route ?? "", kind: m.kind, notification_id: String(m.id) },
      android: { priority: "high", notification: { channel_id: "coupon_pro_ia", tag: `n${m.id}` } },
    },
  };
}

export type SendResult = { ok: true } | { ok: false; unregistered: boolean; error: string };

export async function sendToToken(
  projectId: string,
  bearer: string,
  token: string,
  m: PushMessage,
  fetcher: typeof fetch = fetch,
): Promise<SendResult> {
  const res = await fetcher(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
    body: JSON.stringify(fcmPayload(token, m)),
  });
  if (res.ok) return { ok: true };
  const text = await res.text().catch(() => "");
  // Jeton expiré ou appli désinstallée : le jeton est supprimé.
  const unregistered = res.status === 404 || /UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT.*token/i.test(text);
  return { ok: false, unregistered, error: `FCM ${res.status} ${text.slice(0, 160)}` };
}
