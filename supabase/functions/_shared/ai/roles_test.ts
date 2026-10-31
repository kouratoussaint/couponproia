// Tests : rôles des fournisseurs d'IA, consommation et quotas.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { readQuota } from "./providers.ts";
import { aggregateUsage, type UsageRow, validateRoles } from "./roles.ts";

const known = ["gemini", "groq", "anthropic"];
const configured = (n: string) => n !== "anthropic";

Deno.test("rôles : principale et secours avec clé, sans doublon", () => {
  const ok = validateRoles({ primary: "groq", fallbacks: ["gemini"], models: { groq: "openai/gpt-oss-120b" } }, configured, known);
  assert(ok.ok);
  assertEquals(ok.ok && ok.models.groq, "openai/gpt-oss-120b");
  const noKey = validateRoles({ primary: "anthropic", fallbacks: [], models: {} }, configured, known);
  assert(!noKey.ok && noKey.message.includes("Clé absente"));
  const twice = validateRoles({ primary: "gemini", fallbacks: ["gemini"], models: {} }, configured, known);
  assert(!twice.ok);
  const badModel = validateRoles({ primary: "gemini", fallbacks: [], models: { gemini: "x; drop" } }, configured, known);
  assert(!badModel.ok);
  const fallbackNoKey = validateRoles({ primary: "gemini", fallbacks: ["anthropic"], models: {} }, configured, known);
  assert(!fallbackNoKey.ok);
});

Deno.test("consommation : périodes, rejets, limites atteintes, dernier quota", () => {
  const now = new Date("2026-10-31T20:00:00Z");
  const row = (p: Partial<UsageRow>): UsageRow => ({
    provider: "gemini",
    status: "success",
    input_tokens: 1800,
    output_tokens: 450,
    cost_usd: 0.0017,
    latency_ms: 2400,
    error: null,
    created_at: "2026-10-31T18:00:00Z",
    quota: null,
    ...p,
  });
  const usage = aggregateUsage([
    row({}),
    row({ status: "invalid", latency_ms: 5000 }),
    row({ provider: "groq", status: "error", error: "groq (429) : rate limit", created_at: "2026-10-31T19:00:00Z" }),
    row({
      provider: "groq",
      created_at: "2026-10-31T17:00:00Z",
      quota: { requests_limit: 1000, requests_remaining: 990, requests_reset: "1m", tokens_limit: 8000, tokens_remaining: 7000, tokens_reset: "2s" },
    }),
    row({ created_at: "2026-10-25T10:00:00Z", latency_ms: 1600 }),
  ], now, "Africa/Ouagadougou");
  assertEquals(usage.gemini.today.calls, 2);
  assertEquals(usage.gemini.today.rejected, 1);
  assertEquals(usage.gemini.today.avg_latency_ms, 2400);
  assertEquals(usage.gemini.days_7.calls, 3);
  assertEquals(usage.gemini.days_7.avg_latency_ms, 2000);
  assertEquals(usage.groq.today.rate_limited, 1);
  assertEquals(usage.groq.last_call?.status, "error");
  assertEquals(usage.groq.last_quota?.requests_remaining, 990);
});

Deno.test("quota : en-têtes Groq et Anthropic", () => {
  const groq = readQuota(new Headers({ "x-ratelimit-limit-requests": "1000", "x-ratelimit-remaining-requests": "998", "x-ratelimit-reset-requests": "2m52s" }));
  assertEquals(groq?.requests_remaining, 998);
  assertEquals(groq?.requests_reset, "2m52s");
  const anthropic = readQuota(new Headers({ "anthropic-ratelimit-tokens-remaining": "39000", "anthropic-ratelimit-tokens-limit": "40000" }));
  assertEquals(anthropic?.tokens_limit, 40000);
  assertEquals(readQuota(new Headers({})), null);
});
