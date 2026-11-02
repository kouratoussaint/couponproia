// Lecture et écriture des coupons de l'utilisateur (assistant, générateur manuel, laboratoire).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { ProposedCoupon } from "../coupons/generator.ts";
import { ENGINE_VERSION } from "../engine/poisson.ts";
import type { CouponLine } from "./actions.ts";

export interface StoredLine extends CouponLine {
  marketCode: string;
  outcomeCode: string;
  line: number | null;
}

/** Lignes d'un coupon de l'utilisateur (le coupon en cours de la conversation). */
export async function loadUserCoupon(db: SupabaseClient, userId: string, couponId: string | null, conversationId: string | null) {
  let q = db.from("user_coupons").select(
    "id, criteria, user_coupon_selections(position, match_id, market_code, outcome_code, line, selection_key, odd, model_probability, implied_probability, edge, reliability, match:matches(kickoff_at, home:teams!matches_home_team_fk(name), away:teams!matches_away_team_fk(name), competition:competitions(name)))",
  ).eq("user_id", userId);
  if (couponId) q = q.eq("id", couponId);
  else if (conversationId) q = q.eq("conversation_id", conversationId).order("created_at", { ascending: false });
  else return null;
  const { data } = await q.limit(1).maybeSingle();
  if (!data) return null;
  // deno-lint-ignore no-explicit-any
  const lines: StoredLine[] = (data.user_coupon_selections as any[]).map((s) => ({
    position: s.position,
    matchId: s.match_id,
    home: s.match?.home?.name ?? "?",
    away: s.match?.away?.name ?? "?",
    competition: s.match?.competition?.name ?? "",
    kickoffAt: s.match?.kickoff_at,
    key: s.selection_key,
    marketCode: s.market_code,
    outcomeCode: s.outcome_code,
    line: s.line === null ? null : Number(s.line),
    odd: Number(s.odd),
    modelProbability: Number(s.model_probability),
    impliedProbability: s.implied_probability === null ? null : Number(s.implied_probability),
    edge: s.edge === null ? null : Number(s.edge),
    reliability: s.reliability,
  })).sort((a, b) => a.position - b.position);
  return { id: data.id as string, criteria: data.criteria, lines };
}


export interface NewUserCoupon {
  userId: string;
  conversationId?: string | null;
  messageId?: string | null;
  status: "proposal" | "saved";
  title: string;
  criteria: unknown;
  proposal: ProposedCoupon;
  risk: "prudent" | "equilibre" | "audacieux";
  analysis: Record<string, unknown>;
  /** Langue de l'utilisateur : choisit la justification enregistrée (coupon personnel). */
  lang?: "fr" | "en";
}

function selectionRows(couponId: string, p: ProposedCoupon, lang: "fr" | "en" = "fr") {
  return p.selections.map((s, k) => ({
    coupon_id: couponId,
    position: k + 1,
    match_id: s.matchId,
    market_code: s.marketCode,
    outcome_code: s.outcomeCode,
    line: s.line,
    selection_key: s.key,
    odd: s.odd,
    odd_best: s.oddBest,
    bookmakers: s.bookmakers,
    odds_captured_at: s.oddsCapturedAt,
    model_probability: s.modelProbability,
    implied_probability: s.impliedProbability,
    edge: s.edge,
    reliability: s.reliability,
    justification: lang === "en" ? s.justificationEn ?? s.justification : s.justification,
  }));
}

/** Enregistre un coupon de l'utilisateur et ses sélections (tout ou rien). */
export async function insertUserCoupon(db: SupabaseClient, c: NewUserCoupon): Promise<string> {
  const p = c.proposal;
  const { data: coupon, error } = await db.from("user_coupons").insert({
    user_id: c.userId,
    conversation_id: c.conversationId ?? null,
    message_id: c.messageId ?? null,
    status: c.status,
    title: c.title,
    criteria: c.criteria,
    total_odd: p.totalOdd,
    combined_probability: p.combinedProbability,
    implied_probability: p.impliedProbability,
    risk_level: c.risk,
    analysis: c.analysis,
    engine_version: ENGINE_VERSION,
    fingerprint: p.fingerprint,
  }).select("id").single();
  if (error) throw new Error(error.message);
  const { error: selError } = await db.from("user_coupon_selections").insert(selectionRows(coupon.id, p, c.lang));
  if (selError) {
    await db.from("user_coupons").delete().eq("id", coupon.id);
    throw new Error(selError.message);
  }
  return coupon.id;
}

/** Remplace le contenu d'un coupon de l'utilisateur (générateur manuel). */
export async function replaceUserCoupon(
  db: SupabaseClient,
  couponId: string,
  c: Omit<NewUserCoupon, "userId" | "status" | "conversationId" | "messageId">,
): Promise<void> {
  const p = c.proposal;
  const { error } = await db.from("user_coupons").update({
    title: c.title,
    criteria: c.criteria,
    total_odd: p.totalOdd,
    combined_probability: p.combinedProbability,
    implied_probability: p.impliedProbability,
    risk_level: c.risk,
    analysis: c.analysis,
    engine_version: ENGINE_VERSION,
    fingerprint: p.fingerprint,
  }).eq("id", couponId);
  if (error) throw new Error(error.message);
  await db.from("user_coupon_selections").delete().eq("coupon_id", couponId);
  const { error: selError } = await db.from("user_coupon_selections").insert(selectionRows(couponId, p, c.lang));
  if (selError) throw new Error(selError.message);
}
