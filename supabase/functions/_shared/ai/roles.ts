// Fournisseurs d'IA : validation des rôles choisis par le super administrateur et
// consommation par fournisseur (fonctions pures, testables).
import type { Quota } from "./providers.ts";

export interface UsageRow {
  provider: string;
  status: string;
  input_tokens: number | null;
  output_tokens: number | null;
  cost_usd: number | null;
  latency_ms: number | null;
  error: string | null;
  created_at: string;
  quota: Quota | null;
}

export interface PeriodUsage {
  calls: number;
  success: number;
  rejected: number;
  errors: number;
  rate_limited: number;
  input_tokens: number;
  output_tokens: number;
  cost_usd: number | null;
  avg_latency_ms: number | null;
}

export interface ProviderUsage {
  today: PeriodUsage;
  days_7: PeriodUsage;
  days_30: PeriodUsage;
  last_call: { at: string; status: string; error: string | null } | null;
  last_quota: (Quota & { at: string }) | null;
}

const empty = (): PeriodUsage => ({
  calls: 0,
  success: 0,
  rejected: 0,
  errors: 0,
  rate_limited: 0,
  input_tokens: 0,
  output_tokens: 0,
  cost_usd: null,
  avg_latency_ms: null,
});

const localDay = (d: Date, timeZone: string) =>
  new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);

/** Une requête refusée pour limite atteinte (HTTP 429 ou statut rate_limited). */
export const isRateLimited = (r: Pick<UsageRow, "status" | "error">) =>
  r.status === "rate_limited" || /\(429\)/.test(r.error ?? "");

/** Consommation par fournisseur : aujourd'hui (heure locale), 7 et 30 derniers jours. */
export function aggregateUsage(rows: UsageRow[], now: Date, timeZone: string): Record<string, ProviderUsage> {
  const out: Record<string, ProviderUsage> = {};
  const today = localDay(now, timeZone);
  const latency: Record<string, Record<string, [number, number]>> = {};
  const sorted = [...rows].sort((a, b) => b.created_at.localeCompare(a.created_at));
  for (const r of sorted) {
    const u = out[r.provider] ??= {
      today: empty(),
      days_7: empty(),
      days_30: empty(),
      last_call: null,
      last_quota: null,
    };
    u.last_call ??= { at: r.created_at, status: r.status, error: r.error };
    if (!u.last_quota && r.quota) u.last_quota = { ...r.quota, at: r.created_at };
    const at = new Date(r.created_at);
    const age = now.getTime() - at.getTime();
    const periods: [keyof Omit<ProviderUsage, "last_call" | "last_quota">, boolean][] = [
      ["today", localDay(at, timeZone) === today],
      ["days_7", age <= 7 * 86400_000],
      ["days_30", age <= 30 * 86400_000],
    ];
    for (const [key, inside] of periods) {
      if (!inside) continue;
      const p = u[key];
      p.calls++;
      if (r.status === "success") p.success++;
      else if (r.status === "invalid") p.rejected++;
      else if (isRateLimited(r)) p.rate_limited++;
      else if (r.status === "error") p.errors++;
      p.input_tokens += r.input_tokens ?? 0;
      p.output_tokens += r.output_tokens ?? 0;
      if (r.cost_usd !== null) p.cost_usd = Math.round(((p.cost_usd ?? 0) + Number(r.cost_usd)) * 1e6) / 1e6;
      if (r.status === "success" && r.latency_ms !== null) {
        const l = (latency[r.provider] ??= {})[key] ??= [0, 0];
        l[0] += r.latency_ms;
        l[1]++;
        p.avg_latency_ms = Math.round(l[0] / l[1]);
      }
    }
  }
  return out;
}

export type RolesResult =
  | { ok: true; primary: string; fallbacks: string[]; models: Record<string, string> }
  | { ok: false; message: string };

const MODEL_NAME = /^[A-Za-z0-9._:\/-]{1,100}$/;

/**
 * Rôles demandés : une principale, deux secours au plus, sans doublon ; seuls les
 * fournisseurs dont la clé est configurée peuvent être choisis.
 */
export function validateRoles(
  wanted: { primary: string; fallbacks: string[]; models: Record<string, unknown> },
  configured: (name: string) => boolean,
  known: string[],
): RolesResult {
  const label = (n: string) => n || "(vide)";
  if (!known.includes(wanted.primary)) return { ok: false, message: `IA principale inconnue : ${label(wanted.primary)}.` };
  if (!configured(wanted.primary)) return { ok: false, message: `Clé absente pour ${wanted.primary} : elle ne peut pas être principale.` };
  if (wanted.fallbacks.length > 2) return { ok: false, message: "Deux IA de secours au plus." };
  const seen = new Set([wanted.primary]);
  const fallbacks: string[] = [];
  for (const f of wanted.fallbacks) {
    if (!known.includes(f)) return { ok: false, message: `IA de secours inconnue : ${label(f)}.` };
    if (seen.has(f)) return { ok: false, message: `${f} est choisie deux fois.` };
    seen.add(f);
    // Une IA sans clé ne bloque pas l'enregistrement : elle est simplement retirée des secours.
    if (configured(f)) fallbacks.push(f);
  }
  const models: Record<string, string> = {};
  for (const [name, value] of Object.entries(wanted.models)) {
    if (!known.includes(name)) return { ok: false, message: `Fournisseur inconnu : ${name}.` };
    if (typeof value !== "string" || !MODEL_NAME.test(value)) return { ok: false, message: `Nom de modèle invalide pour ${name}.` };
    models[name] = value;
  }
  return { ok: true, primary: wanted.primary, fallbacks, models };
}
