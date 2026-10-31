// Fournisseurs d'IA interchangeables. Les clés restent côté serveur (secrets Supabase).
// Chaque appel renvoie le texte brut et les tokens consommés, pour le journal des coûts.

export type FetchFn = typeof fetch;

export interface AiCallResult {
  text: string;
  model: string;
  inputTokens: number | null;
  outputTokens: number | null;
  /** Quota restant annoncé par le fournisseur (en-têtes de limite), s'il en envoie. */
  quota?: Quota | null;
}

/** Limites et restes annoncés par le fournisseur ; les remises à zéro sont en texte brut. */
export interface Quota {
  requests_limit: number | null;
  requests_remaining: number | null;
  requests_reset: string | null;
  tokens_limit: number | null;
  tokens_remaining: number | null;
  tokens_reset: string | null;
}

/** Lit les en-têtes de limite (Groq : x-ratelimit-*, Anthropic : anthropic-ratelimit-*). */
export function readQuota(headers: Headers): Quota | null {
  const num = (name: string) => {
    const v = headers.get(name);
    const n = v === null ? NaN : Number(v);
    return Number.isFinite(n) ? n : null;
  };
  const groq = {
    requests_limit: num("x-ratelimit-limit-requests"),
    requests_remaining: num("x-ratelimit-remaining-requests"),
    requests_reset: headers.get("x-ratelimit-reset-requests"),
    tokens_limit: num("x-ratelimit-limit-tokens"),
    tokens_remaining: num("x-ratelimit-remaining-tokens"),
    tokens_reset: headers.get("x-ratelimit-reset-tokens"),
  };
  const anthropic = {
    requests_limit: num("anthropic-ratelimit-requests-limit"),
    requests_remaining: num("anthropic-ratelimit-requests-remaining"),
    requests_reset: headers.get("anthropic-ratelimit-requests-reset"),
    tokens_limit: num("anthropic-ratelimit-tokens-limit"),
    tokens_remaining: num("anthropic-ratelimit-tokens-remaining"),
    tokens_reset: headers.get("anthropic-ratelimit-tokens-reset"),
  };
  const filled = (q: Quota) => q.requests_remaining !== null || q.tokens_remaining !== null;
  return filled(groq) ? groq : filled(anthropic) ? anthropic : null;
}

export interface AiProvider {
  readonly name: string;
  call(system: string, user: string, model: string): Promise<AiCallResult>;
}

export class AiProviderError extends Error {
  constructor(
    readonly provider: string,
    readonly status: number,
    message: string,
    readonly quota: Quota | null = null,
  ) {
    super(`${provider} (${status}) : ${message}`);
  }
}

async function errorText(res: Response): Promise<string> {
  const body = await res.text().catch(() => "");
  return body.slice(0, 300);
}

/** Google Gemini (API Gemini Developer, clé AI Studio). */
export class GeminiProvider implements AiProvider {
  readonly name = "gemini";
  private resolvedModel: string | null = null;
  private static readonly base = "https://generativelanguage.googleapis.com/v1beta";

  constructor(private readonly apiKey: string, private readonly fetchFn: FetchFn = fetch) {}

  private async generate(system: string, user: string, model: string): Promise<Response> {
    return await this.fetchFn(`${GeminiProvider.base}/models/${encodeURIComponent(model)}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": this.apiKey },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts: [{ text: user }] }],
        generationConfig: { responseMimeType: "application/json", temperature: 0.3, maxOutputTokens: 4096 },
      }),
    });
  }

  /** Modèle demandé introuvable : on prend le plus récent « flash-lite », sinon « flash ». */
  async pickAvailableModel(): Promise<string | null> {
    const res = await this.fetchFn(`${GeminiProvider.base}/models?pageSize=200`, {
      headers: { "x-goog-api-key": this.apiKey },
    });
    if (!res.ok) return null;
    const body = await res.json();
    const names: string[] = (body?.models ?? [])
      .filter((m: { supportedGenerationMethods?: string[] }) =>
        (m.supportedGenerationMethods ?? []).includes("generateContent")
      )
      .map((m: { name: string }) => String(m.name).replace(/^models\//, ""))
      .filter((n: string) => /^gemini-[\d.]+-flash/.test(n) && !/(preview|exp|image|audio|tts|live)/.test(n));
    const version = (n: string) => parseFloat(n.split("-")[1]) || 0;
    const best = (pred: (n: string) => boolean) =>
      names.filter(pred).sort((a, b) => version(b) - version(a) || a.length - b.length)[0] ?? null;
    return best((n) => n.includes("flash-lite")) ?? best(() => true);
  }

  async call(system: string, user: string, model: string): Promise<AiCallResult> {
    let useModel = this.resolvedModel ?? model;
    let res = await this.generate(system, user, useModel);
    if (res.status === 404) {
      const alt = await this.pickAvailableModel();
      if (alt && alt !== useModel) {
        useModel = alt;
        res = await this.generate(system, user, useModel);
      }
    }
    if (!res.ok) throw new AiProviderError(this.name, res.status, await errorText(res));
    this.resolvedModel = useModel;
    const body = await res.json();
    const parts = body?.candidates?.[0]?.content?.parts ?? [];
    const text = parts.filter((p: { thought?: boolean }) => !p.thought)
      .map((p: { text?: string }) => p.text ?? "").join("");
    if (!text) throw new AiProviderError(this.name, 200, `réponse vide (${body?.candidates?.[0]?.finishReason ?? "?"})`);
    return {
      text,
      model: useModel,
      inputTokens: body?.usageMetadata?.promptTokenCount ?? null,
      outputTokens: (body?.usageMetadata?.candidatesTokenCount ?? 0) + (body?.usageMetadata?.thoughtsTokenCount ?? 0) ||
        null,
    };
  }
}

/** Anthropic Claude (API Messages). */
export class AnthropicProvider implements AiProvider {
  readonly name = "anthropic";
  constructor(private readonly apiKey: string, private readonly fetchFn: FetchFn = fetch) {}

  async call(system: string, user: string, model: string): Promise<AiCallResult> {
    const res = await this.fetchFn("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({ model, max_tokens: 2048, system, messages: [{ role: "user", content: user }] }),
    });
    if (!res.ok) throw new AiProviderError(this.name, res.status, await errorText(res), readQuota(res.headers));
    const body = await res.json();
    const text = (body?.content ?? []).filter((c: { type: string }) => c.type === "text")
      .map((c: { text: string }) => c.text).join("");
    return {
      text,
      model: body?.model ?? model,
      inputTokens: body?.usage?.input_tokens ?? null,
      outputTokens: body?.usage?.output_tokens ?? null,
      quota: readQuota(res.headers),
    };
  }
}

/** Groq (API compatible OpenAI). */
export class GroqProvider implements AiProvider {
  readonly name = "groq";
  constructor(private readonly apiKey: string, private readonly fetchFn: FetchFn = fetch) {}

  async call(system: string, user: string, model: string): Promise<AiCallResult> {
    const res = await this.fetchFn("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${this.apiKey}` },
      body: JSON.stringify({
        model,
        temperature: 0.3,
        response_format: { type: "json_object" },
        messages: [{ role: "system", content: system }, { role: "user", content: user }],
      }),
    });
    if (!res.ok) throw new AiProviderError(this.name, res.status, await errorText(res), readQuota(res.headers));
    const body = await res.json();
    return {
      text: body?.choices?.[0]?.message?.content ?? "",
      model: body?.model ?? model,
      inputTokens: body?.usage?.prompt_tokens ?? null,
      outputTokens: body?.usage?.completion_tokens ?? null,
      quota: readQuota(res.headers),
    };
  }
}

/** Construit un fournisseur si sa clé est configurée. */
export function makeProvider(
  name: string,
  env: (key: string) => string | undefined,
  fetchFn: FetchFn = fetch,
): AiProvider | null {
  const keys: Record<string, string> = {
    gemini: "GEMINI_API_KEY",
    anthropic: "ANTHROPIC_API_KEY",
    groq: "GROQ_API_KEY",
  };
  const key = keys[name] ? env(keys[name]) : undefined;
  if (!key) return null;
  if (name === "gemini") return new GeminiProvider(key, fetchFn);
  if (name === "anthropic") return new AnthropicProvider(key, fetchFn);
  return new GroqProvider(key, fetchFn);
}

/** Fournisseurs connus : nom affiché et secret de la clé. */
export const PROVIDERS: Record<string, { label: string; secret: string }> = {
  gemini: { label: "Gemini", secret: "GEMINI_API_KEY" },
  groq: { label: "Groq", secret: "GROQ_API_KEY" },
  anthropic: { label: "Claude", secret: "ANTHROPIC_API_KEY" },
};

/** Modèles proposés par le fournisseur (appel en direct, avec la clé du serveur). */
export async function listModels(name: string, apiKey: string, fetchFn: FetchFn = fetch): Promise<string[]> {
  if (name === "gemini") {
    const res = await fetchFn("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", {
      headers: { "x-goog-api-key": apiKey },
    });
    if (!res.ok) throw new AiProviderError(name, res.status, await errorText(res));
    const body = await res.json();
    return (body?.models ?? [])
      .filter((m: { supportedGenerationMethods?: string[] }) =>
        (m.supportedGenerationMethods ?? []).includes("generateContent")
      )
      .map((m: { name: string }) => String(m.name).replace(/^models\//, ""))
      .filter((n: string) => n.startsWith("gemini-"))
      .sort();
  }
  const url = name === "groq" ? "https://api.groq.com/openai/v1/models" : "https://api.anthropic.com/v1/models?limit=100";
  const headers: Record<string, string> = name === "groq"
    ? { Authorization: `Bearer ${apiKey}` }
    : { "x-api-key": apiKey, "anthropic-version": "2023-06-01" };
  const res = await fetchFn(url, { headers });
  if (!res.ok) throw new AiProviderError(name, res.status, await errorText(res));
  const body = await res.json();
  return (body?.data ?? []).map((m: { id: string }) => String(m.id)).sort();
}
