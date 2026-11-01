// Edge Function : Laboratoire IA et générateur manuel.
//
// Tous les calculs sont faits ici, côté serveur : cote totale, probabilités du modèle,
// contrôles des sélections. Actions : build (coupon manuel), analyze, optimize, compare,
// simulate (étiquetée comme simulation). Aucune action n'appelle l'IA. La composition manuelle
// est gratuite ; avec le forfait FREE, chaque calcul coûte `lab.credit_cost` crédits (débités
// seulement quand le calcul aboutit) ; forfaits payants et équipe : gratuit.
import { diagnoseCoupon } from "../_shared/assistant/actions.ts";
import { insertUserCoupon, loadUserCoupon, replaceUserCoupon, type StoredLine } from "../_shared/assistant/store.ts";
import { loadCandidates, loadLiveChecks } from "../_shared/coupons/data.ts";
import { type Candidate, defaultSummary, riskLevel, type RiskThresholds } from "../_shared/coupons/generator.ts";
import { loadEngineQuality } from "../_shared/engine/quality.ts";
import { alternativesFor, compareCoupons, simulate } from "../_shared/lab/lab.ts";
import { labDecision } from "../_shared/lab/pricing.ts";
import { planFeatures } from "../_shared/billing.ts";
import { callerFrom, corsHeaders, json, readSettings, serverContext } from "../_shared/http.ts";

const MAX_SELECTIONS = 12;

function proposalOf(selections: Candidate[]) {
  const sorted = [...selections].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));
  const implied = sorted.every((s) => s.impliedProbability !== null)
    ? Math.round(sorted.reduce((p, s) => p * (s.impliedProbability as number), 1) * 10000) / 10000
    : null;
  return {
    selections: sorted,
    totalOdd: Math.round(sorted.reduce((p, s) => p * s.odd, 1) * 100) / 100,
    combinedProbability: Math.round(sorted.reduce((p, s) => p * s.modelProbability, 1) * 10000) / 10000,
    impliedProbability: implied,
    fingerprint: sorted.map((s) => `${s.matchId}:${s.key}`).sort().join("|"),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const caller = await callerFrom(req, ctx);
  if (!caller) return json({ error: "unauthorized" }, 401);
  const { db } = ctx;
  const body = await req.json().catch(() => ({}));
  const action = String(body?.action ?? "");
  const now = new Date();

  try {
    const { data: flag } = await db.from("feature_flags").select("enabled").eq("key", "ai_lab").maybeSingle();
    if (!flag?.enabled) return json({ error: "feature_disabled" }, 403);
    const quality = await loadEngineQuality(db);
    const settings = await readSettings(db, ["coupons.risk_thresholds", "lab.credit_cost"]);
    const thresholds = (settings["coupons.risk_thresholds"] ?? { prudent: 0.4, equilibre: 0.18 }) as RiskThresholds;

    // Prix du calcul (forfait FREE) : refusé d'avance sans assez de crédits.
    let charge = 0;
    if (action !== "build") {
      const { plan } = await planFeatures(db, caller.id);
      const { data: summary } = await db.rpc("svc_credit_summary", { p_user: caller.id });
      const d = labDecision(action, summary, plan, Number(settings["lab.credit_cost"] ?? 1));
      if (!d.ok) return json({ error: "credits_required", cost: d.cost }, 402);
      charge = d.cost;
    }
    // Résultat d'un calcul : débit des crédits, puis réponse (rien n'est rendu sans débit).
    const paid = async (payload: Record<string, unknown>) => {
      if (charge > 0) {
        const { error } = await db.rpc("svc_consume_credits", {
          p_user: caller.id,
          p_operation: crypto.randomUUID(),
          p_amount: charge,
          p_kind: `lab:${action}`,
        });
        if (error) return json({ error: "credits_required", cost: charge }, 402);
      }
      return json({ ...payload, credits_used: charge });
    };

    const own = async (id: unknown) => {
      if (typeof id !== "string") return null;
      return await loadUserCoupon(db, caller.id, id, null);
    };

    // ---------------------------------------------------------------------
    if (action === "build") {
      const raw = Array.isArray(body?.selections) ? body.selections : [];
      const wanted = raw.slice(0, MAX_SELECTIONS + 1).map((s: { match_id: unknown; key: unknown }) => ({
        matchId: Number(s?.match_id),
        key: String(s?.key ?? "").toUpperCase(),
      })).filter((s: { matchId: number; key: string }) => Number.isInteger(s.matchId) && s.key);
      if (wanted.length === 0) return json({ error: "no_selection" }, 400);
      if (wanted.length > MAX_SELECTIONS) return json({ error: "too_many", max: MAX_SELECTIONS }, 400);
      const errors: string[] = [];
      if (new Set(wanted.map((w: { matchId: number }) => w.matchId)).size !== wanted.length) {
        errors.push("Une seule sélection par match : deux issues d'un même match ne peuvent pas être combinées.");
      }
      const load = await loadCandidates(db, now, 168, quality, undefined, wanted.map((w: { matchId: number }) => w.matchId));
      const chosen: Candidate[] = [];
      for (const w of wanted) {
        const c = load.candidates.find((x) => x.matchId === w.matchId && x.key === w.key);
        if (!c) {
          errors.push(`Match ${w.matchId} : issue ${w.key} indisponible (match commencé, hors programme ou plus cotée).`);
        } else if (Date.parse(c.kickoffAt) <= now.getTime()) {
          errors.push(`${c.home} – ${c.away} : le match a commencé.`);
        } else chosen.push(c);
      }
      if (errors.length) return json({ error: "invalid_selections", errors }, 422);
      const p = proposalOf(chosen);
      const risk = riskLevel(p.combinedProbability, thresholds);
      const analysis = { ...defaultSummary(p), source: "calcul", manual: true };
      const title = `Mon coupon · ${p.selections.length} sélection${p.selections.length > 1 ? "s" : ""} · cote ${p.totalOdd.toFixed(2).replace(".", ",")}`;
      const existing = await own(body?.coupon_id);
      let id: string;
      if (existing) {
        await replaceUserCoupon(db, existing.id, { title, criteria: { source: "manuel" }, proposal: p, risk, analysis });
        id = existing.id;
      } else {
        id = await insertUserCoupon(db, {
          userId: caller.id,
          status: body?.save === true ? "saved" : "proposal",
          title,
          criteria: { source: "manuel" },
          proposal: p,
          risk,
          analysis,
        });
      }
      return json({
        coupon_id: id,
        total_odd: p.totalOdd,
        combined_probability: p.combinedProbability,
        implied_probability: p.impliedProbability,
        risk_level: risk,
      });
    }

    // ---------------------------------------------------------------------
    const withLive = async (lines: StoredLine[]) => {
      const live = await loadLiveChecks(db, lines.map((l) => ({ matchId: l.matchId, key: l.key })));
      return lines.map((l) => {
        const x = live.get(`${l.matchId}:${l.key}`);
        return { ...l, status: x?.status ?? undefined, currentOdd: x ? x.currentOdd : undefined };
      });
    };

    if (action === "analyze" || action === "optimize" || action === "simulate") {
      const coupon = await own(body?.coupon_id);
      if (!coupon || coupon.lines.length === 0) return json({ error: "coupon_not_found" }, 404);
      if (action === "analyze") {
        return await paid({ diagnosis: diagnoseCoupon(await withLive(coupon.lines), quality?.beatsBaseline ?? null, now) });
      }
      if (action === "simulate") {
        const runs = Math.min(10000, Math.max(100, Number(body?.runs) || 1000));
        const total = coupon.lines.reduce((x, l) => x * l.odd, 1);
        return await paid({ simulation: simulate(coupon.lines.map((l) => l.modelProbability), total, runs) });
      }
      const lastKickoff = Math.max(...coupon.lines.map((l) => Date.parse(l.kickoffAt)));
      const hours = Math.max(24, (lastKickoff - now.getTime()) / 3600_000 + 12);
      const load = await loadCandidates(db, now, hours, quality);
      const fresh = load.candidates.filter((c) => Date.parse(c.kickoffAt) - now.getTime() > 15 * 60_000);
      return await paid({
        alternatives: alternativesFor(coupon.lines, fresh),
        note: "Alternatives plus probables selon le modèle ; la cote du coupon change en conséquence. Vous choisissez.",
      });
    }

    if (action === "compare") {
      const ids = Array.isArray(body?.coupon_ids) ? body.coupon_ids.slice(0, 3) : [];
      if (ids.length < 2) return json({ error: "need_two_coupons" }, 400);
      const coupons = [];
      for (const id of ids) {
        const c = await own(id);
        if (!c) return json({ error: "coupon_not_found" }, 404);
        const { data: head } = await db.from("user_coupons").select("title").eq("id", c.id).single();
        coupons.push({ id: c.id, title: head?.title ?? "", lines: c.lines });
      }
      return await paid({
        comparison: compareCoupons(coupons, quality?.beatsBaseline ?? null),
        note: "Probabilités du modèle, sélections supposées indépendantes ; les paires d'une même compétition le même jour peuvent être liées.",
      });
    }

    return json({ error: "unknown_action", allowed: ["build", "analyze", "optimize", "compare", "simulate"] }, 400);
  } catch (e) {
    console.error("lab", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
