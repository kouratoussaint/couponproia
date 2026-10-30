// Edge Function : règlement des coupons (plateforme et utilisateurs).
// Appelée par pg_cron toutes les 30 minutes (secret) ou par un administrateur. Relit l'état
// des matchs, applique les règles centralisées (_shared/settlement), n'écrit que ce qui
// change et historise chaque règlement ; un résultat qui change ensuite est une correction.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { callerFrom, corsHeaders, env, json, serverContext } from "../_shared/http.ts";
import { couponResult, type MatchState, selectionResult, type SelectionResult } from "../_shared/settlement/settle.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

const RECHECK_DAYS = 3;

interface Sel {
  id: number;
  match_id: number;
  selection_key: string;
  odd: number;
  result: string | null;
}
interface CouponRow {
  id: string;
  result: string | null;
  settled_odd: number | null;
  sels: Sel[];
}

async function loadMatches(db: SupabaseClient, ids: number[]): Promise<Map<number, MatchState>> {
  const out = new Map<number, MatchState>();
  for (let i = 0; i < ids.length; i += 200) {
    const { data, error } = await db.from("matches")
      .select("id, status, status_short, kickoff_at, home_goals, away_goals, ft_home_goals, ft_away_goals")
      .in("id", ids.slice(i, i + 200));
    if (error) throw new Error(error.message);
    for (const m of data ?? []) {
      out.set(m.id, {
        status: m.status,
        statusShort: m.status_short,
        kickoffAt: m.kickoff_at,
        homeGoals: m.home_goals,
        awayGoals: m.away_goals,
        ftHomeGoals: m.ft_home_goals,
        ftAwayGoals: m.ft_away_goals,
      });
    }
  }
  return out;
}

async function settleKind(db: SupabaseClient, kind: "platform" | "user", now: Date) {
  const table = kind === "platform" ? "coupons" : "user_coupons";
  const selTable = kind === "platform" ? "coupon_selections" : "user_coupon_selections";
  const since = new Date(now.getTime() - RECHECK_DAYS * 86400_000).toISOString();
  let q = db.from(table).select(`id, result, settled_odd, sels:${selTable}(id, match_id, selection_key, odd, result)`)
    .or(`result.is.null,settled_at.gte.${since}`).limit(500);
  q = kind === "platform"
    ? q.in("status", ["published", "withdrawn"]).lte("first_kickoff_at", now.toISOString())
    : q.eq("status", "saved");
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  const coupons = (data ?? []) as unknown as CouponRow[];
  const matches = await loadMatches(db, [...new Set(coupons.flatMap((c) => c.sels.map((s) => s.match_id)))]);

  let settled = 0;
  let corrections = 0;
  let selectionUpdates = 0;
  for (const c of coupons) {
    const results = c.sels.map((s) => {
      const m = matches.get(s.match_id);
      const r: SelectionResult = m ? selectionResult(s.selection_key, m, now) : "pending";
      return { sel: s, result: r };
    });
    // Sélections : enregistrer chaque issue connue (ou son retour en attente après correction).
    for (const { sel, result } of results) {
      const stored = result === "pending" ? null : result;
      if (stored !== sel.result) {
        const { error: e } = await db.from(selTable).update({ result: stored }).eq("id", sel.id);
        if (e) throw new Error(e.message);
        selectionUpdates++;
      }
    }
    const outcome = couponResult(results.map((r) => ({ result: r.result, odd: Number(r.sel.odd) })));
    const newResult = outcome.result === "pending" ? null : outcome.result;
    const newOdd = outcome.settledOdd;
    if (newResult === c.result && (newResult === null || Number(newOdd) === Number(c.settled_odd))) continue;

    const isCorrection = c.result !== null;
    const { error: e } = await db.from(table).update({
      result: newResult,
      settled_odd: newOdd,
      settled_at: newResult === null ? null : now.toISOString(),
    }).eq("id", c.id);
    if (e) throw new Error(e.message);
    await db.from("settlement_history").insert({
      coupon_kind: kind,
      coupon_id: c.id,
      previous_result: c.result,
      new_result: newResult,
      previous_odd: c.settled_odd,
      new_odd: newOdd,
      is_correction: isCorrection,
      selections: results.map((r) => ({ match_id: r.sel.match_id, key: r.sel.selection_key, result: r.result })),
    });
    if (isCorrection) corrections++;
    else settled++;
  }
  return { checked: coupons.length, settled, corrections, selectionUpdates };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const cronSecret = env("CRON_SECRET");
  const header = req.headers.get("x-cron-secret");
  const fromCron = Boolean(cronSecret && header && safeEqual(header, cronSecret));
  if (!fromCron) {
    const caller = await callerFrom(req, ctx);
    if (!caller) return json({ error: "unauthorized" }, 401);
    if (!caller.permissions.includes("generation.manage")) return json({ error: "forbidden" }, 403);
  }
  try {
    const now = new Date();
    const platform = await settleKind(ctx.db, "platform", now);
    const user = await settleKind(ctx.db, "user", now);
    return json({ platform, user });
  } catch (e) {
    console.error("settle-coupons", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
