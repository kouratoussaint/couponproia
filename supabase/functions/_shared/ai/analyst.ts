// Orchestration : fiche → IA → validation → (correction) → analyse publiée ou repli.
// Les fournisseurs sont essayés dans l'ordre ; chaque tentative est journalisée.
import { type AiProvider, AiProviderError } from "./providers.ts";
import { type Analysis, type FicheLike, parseJsonLoose, validateAnalysis } from "./validate.ts";

export type Validator<T> = (raw: unknown) => { ok: true; value: T } | { ok: false; errors: string[] };

export interface ProviderChoice {
  provider: AiProvider;
  model: string;
}

export interface AttemptLog {
  provider: string;
  model: string;
  status: "success" | "invalid" | "error";
  attempts: number;
  inputTokens: number | null;
  outputTokens: number | null;
  costUsd: number | null;
  latencyMs: number;
  error: string | null;
}

export type AiResult<T> =
  | { status: "ok"; value: T; provider: string; model: string; logs: AttemptLog[] }
  | { status: "stats_only"; reason: string; logs: AttemptLog[] };

export type AnalystResult =
  | { status: "ok"; analysis: Analysis; provider: string; model: string; logs: AttemptLog[] }
  | { status: "stats_only"; reason: string; logs: AttemptLog[] };

export type Pricing = Record<string, [number, number]>;

export function estimateCost(pricing: Pricing, model: string, input: number | null, output: number | null): number | null {
  const price = pricing[model];
  if (!price || input === null || output === null) return null;
  return Math.round((input * price[0] + output * price[1])) / 1e6;
}

const add = (a: number | null, b: number | null) => (a === null && b === null ? null : (a ?? 0) + (b ?? 0));

export async function analyzeWithAi(
  fiche: FicheLike,
  systemPrompt: string,
  choices: ProviderChoice[],
  pricing: Pricing = {},
  now: () => number = Date.now,
): Promise<AnalystResult> {
  const r = await runValidated(fiche, systemPrompt, choices, (raw) => {
    const v = validateAnalysis(raw, fiche);
    return v.ok ? { ok: true, value: v.analysis } : v;
  }, pricing, now);
  return r.status === "ok" ? { status: "ok", analysis: r.value, provider: r.provider, model: r.model, logs: r.logs } : r;
}

/**
 * Appelle les fournisseurs dans l'ordre ; chaque réponse passe par `validate`. Une réponse
 * refusée est redemandée une fois avec la liste des erreurs, puis on passe au suivant.
 */
export async function runValidated<T>(
  fiche: unknown,
  systemPrompt: string,
  choices: ProviderChoice[],
  validate: Validator<T>,
  pricing: Pricing = {},
  now: () => number = Date.now,
): Promise<AiResult<T>> {
  if (choices.length === 0) return { status: "stats_only", reason: "no_provider", logs: [] };
  const logs: AttemptLog[] = [];
  const user = `FICHE :\n${JSON.stringify(fiche)}`;
  for (const { provider, model } of choices) {
    const started = now();
    const log: AttemptLog = {
      provider: provider.name,
      model,
      status: "error",
      attempts: 0,
      inputTokens: null,
      outputTokens: null,
      costUsd: null,
      latencyMs: 0,
      error: null,
    };
    logs.push(log);
    let message = user;
    try {
      for (let attempt = 1; attempt <= 2; attempt++) {
        log.attempts = attempt;
        const res = await provider.call(systemPrompt, message, model);
        log.model = res.model;
        log.inputTokens = add(log.inputTokens, res.inputTokens);
        log.outputTokens = add(log.outputTokens, res.outputTokens);
        let errors: string[];
        try {
          const verdict = validate(parseJsonLoose(res.text));
          if (verdict.ok) {
            log.status = "success";
            log.latencyMs = now() - started;
            log.costUsd = estimateCost(pricing, log.model, log.inputTokens, log.outputTokens);
            return { status: "ok", value: verdict.value, provider: provider.name, model: log.model, logs };
          }
          errors = verdict.errors;
        } catch (e) {
          errors = [`JSON invalide : ${(e as Error).message}`];
        }
        log.status = "invalid";
        log.error = errors.join(" | ").slice(0, 500);
        message = `${user}\n\nTa réponse précédente a été refusée :\n- ${errors.join("\n- ")}\n` +
          "Corrige ces points et renvoie uniquement l'objet JSON complet.";
      }
    } catch (e) {
      log.status = "error";
      log.error = (e instanceof AiProviderError ? e.message : String(e)).slice(0, 500);
    }
    log.latencyMs = now() - started;
    log.costUsd = estimateCost(pricing, log.model, log.inputTokens, log.outputTokens);
  }
  const reason = logs.every((l) => l.status === "error") ? "provider_error" : "validation_failed";
  return { status: "stats_only", reason, logs };
}
