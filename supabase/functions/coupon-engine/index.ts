// Edge Function : moteur des coupons de la plateforme.
//
//  - « tick » (pg_cron, toutes les 15 min) : génère les créneaux programmés échus,
//    les profils continus quand de nouvelles cotes sont arrivées, puis publie les coupons
//    prêts dont l'heure est venue (avec un dernier contrôle).
//  - « generate » (administrateur generation.manage, ou exploitation via le secret) : génère
//    tout de suite pour un profil.
// Chaque génération est journalisée (generation_runs), y compris ses refus motivés.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { type AiResult, runValidated } from "../_shared/ai/analyst.ts";
import { loadAiSetup } from "../_shared/ai/setup.ts";
import { type CouponSummary, validateCouponSummary } from "../_shared/ai/validate.ts";
import { type CandidateLoad, liveFingerprints, loadCandidates, loadLiveChecks } from "../_shared/coupons/data.ts";
import {
  buildCoupons,
  type Criteria,
  defaultSummary,
  filterCandidates,
  outcomeLabel,
  parseCriteria,
  type ProposedCoupon,
  qualityCheck,
  riskLevel,
  type RiskThresholds,
} from "../_shared/coupons/generator.ts";
import { dueSlots, localDate, type Slot } from "../_shared/coupons/schedule.ts";
import { loadEngineQuality } from "../_shared/engine/quality.ts";
import { ENGINE_VERSION } from "../_shared/engine/poisson.ts";
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

type Trigger = "schedule" | "continuous" | "manual";

interface Profile {
  id: number;
  key: string;
  name: string;
  category: string;
  description: string | null;
  is_active: boolean;
  mode: "scheduled" | "continuous";
  publish_mode: "auto" | "review";
  generate_times: string[];
  publish_delay_minutes: number;
  continuous_min_interval_minutes: number;
  criteria: unknown;
}

interface RunSummary {
  profile: string;
  trigger: Trigger;
  slot: string | null;
  status: string;
  coupons: number;
  reasons: string[];
}

const pct = (p: number) => `${Math.round(p * 100)} %`;
const dec = (x: number) => x.toFixed(2).replace(".", ",");

class CouponEngine {
  private settings: Record<string, unknown> = {};
  private candidateCache = new Map<number, Promise<CandidateLoad>>();
  private quality: Awaited<ReturnType<typeof loadEngineQuality>> = null;

  constructor(private readonly db: SupabaseClient, private readonly now: Date) {}

  async init() {
    this.settings = await readSettings(this.db, [
      "app.timezone",
      "coupons.risk_thresholds",
      "coupons.max_publications_per_day",
      "coupons.data_freshness_hours",
      "ai.coupon_summary",
    ]);
    this.quality = await loadEngineQuality(this.db);
  }

  get timeZone() {
    return String(this.settings["app.timezone"] ?? "Africa/Ouagadougou");
  }

  private candidates(windowHours: number) {
    const w = Math.ceil(windowHours);
    if (!this.candidateCache.has(w)) this.candidateCache.set(w, loadCandidates(this.db, this.now, w, this.quality));
    return this.candidateCache.get(w)!;
  }

  // -------------------------------------------------------------------------
  async generate(profile: Profile, trigger: Trigger, slot: Slot | null, actorId: string | null): Promise<RunSummary | null> {
    const { data: run, error: runError } = await this.db.from("generation_runs").insert({
      profile_id: profile.id,
      trigger,
      slot_key: slot?.slotKey ?? null,
      actor_id: actorId,
    }).select("id").single();
    if (runError) {
      if (runError.code === "23505") return null; // créneau déjà traité
      throw new Error(runError.message);
    }
    const criteria = parseCriteria(profile.criteria);
    const reasons: string[] = [];
    const details: Record<string, unknown> = { criteria };
    let created = 0;
    let candidatesCount = 0;
    let failed = false;
    try {
      created = await this.generateInner(profile, criteria, trigger, slot, run.id, reasons, details, (n) => candidatesCount = n);
    } catch (e) {
      failed = true;
      reasons.push(`Erreur technique : ${String((e as Error).message ?? e).slice(0, 200)}`);
    }
    const status = failed
      ? "failed"
      : created === 0
      ? "refused"
      : created < criteria.coupons_per_run
      ? "partial"
      : "success";
    await this.db.from("generation_runs").update({
      status,
      candidates: candidatesCount,
      coupons_created: created,
      reasons,
      details,
      finished_at: new Date().toISOString(),
    }).eq("id", run.id);
    return { profile: profile.key, trigger, slot: slot?.slotKey ?? null, status, coupons: created, reasons };
  }

  private async generateInner(
    profile: Profile,
    criteria: Criteria,
    trigger: Trigger,
    slot: Slot | null,
    runId: number,
    reasons: string[],
    details: Record<string, unknown>,
    setCandidates: (n: number) => void,
  ): Promise<number> {
    // Fraîcheur des données : dernière synchronisation réussie des calendriers.
    const freshness = Number(this.settings["coupons.data_freshness_hours"] ?? 30);
    const { data: lastSync } = await this.db.from("sync_runs").select("finished_at")
      .eq("job", "daily").in("status", ["success", "partial"]).order("finished_at", { ascending: false })
      .limit(1).maybeSingle();
    if (!lastSync?.finished_at || this.now.getTime() - Date.parse(lastSync.finished_at) > freshness * 3600_000) {
      reasons.push(
        `Données trop anciennes : dernière synchronisation des calendriers ${lastSync?.finished_at ?? "inconnue"} (plus de ${freshness} h).`,
      );
      return 0;
    }

    // Plafond quotidien de coupons, tous profils confondus.
    const cap = Number(this.settings["coupons.max_publications_per_day"] ?? 12);
    const dayStart = new Date(Date.parse(`${localDate(this.now, this.timeZone)}T00:00:00Z`));
    const { count } = await this.db.from("coupons").select("id", { count: "exact", head: true })
      .in("status", ["pending_review", "ready", "published"]).gte("created_at", dayStart.toISOString());
    if ((count ?? 0) >= cap) {
      reasons.push(`Plafond quotidien atteint (${cap} coupons).`);
      return 0;
    }

    const load = await this.candidates(criteria.window_hours);
    setCandidates(load.candidates.length);
    details.upcoming_matches = load.upcomingMatches;
    details.matches_with_odds = load.matchesWithOdds;
    if (load.candidates.length === 0) {
      reasons.push(
        load.upcomingMatches === 0
          ? `Aucun match programmé dans les ${criteria.window_hours} prochaines heures.`
          : `Aucune cote disponible pour les ${load.upcomingMatches} matchs des ${criteria.window_hours} prochaines heures.`,
      );
      return 0;
    }
    if (!this.quality) reasons.push("Moteur jamais évalué : aucun marché n'est validé.");
    const { kept, excluded } = filterCandidates(
      load.candidates,
      criteria,
      this.now,
      this.quality?.beatsBaseline ?? null,
      this.quality?.competitions ?? {},
    );
    details.excluded = excluded;
    details.kept = kept.length;
    if (new Set(kept.map((c) => c.matchId)).size < criteria.min_selections) {
      const top = Object.entries(excluded).sort((a, b) => b[1] - a[1]).slice(0, 3)
        .map(([why, n]) => `${why} (${n})`).join(", ");
      reasons.push(
        `Pas assez de sélections conformes aux critères : ${new Set(kept.map((c) => c.matchId)).size} match(s) sur ${criteria.min_selections} requis. Principaux motifs : ${top || "aucun"}.`,
      );
      return 0;
    }

    const taken = await liveFingerprints(this.db);
    const proposals = buildCoupons(kept, criteria, taken);
    if (proposals.length === 0) {
      reasons.push(
        `Aucune combinaison de ${criteria.min_selections} à ${criteria.max_selections} sélections avec une cote totale entre ${dec(criteria.min_total_odd)} et ${dec(criteria.max_total_odd)}.`,
      );
      return 0;
    }

    let created = 0;
    for (const proposal of proposals) {
      const live = await loadLiveChecks(this.db, proposal.selections);
      const qc = qualityCheck(proposal, live, criteria, this.now, taken);
      if (qc.length) {
        reasons.push(`Coupon refusé au contrôle qualité : ${qc.join(" ; ")}.`);
        continue;
      }
      const ok = await this.saveCoupon(profile, criteria, trigger, slot, runId, proposal, reasons);
      if (ok) {
        created++;
        taken.add(proposal.fingerprint);
      }
    }
    return created;
  }

  private couponFiche(p: ProposedCoupon, risk: string) {
    return {
      total_odd: p.totalOdd,
      combined_probability: p.combinedProbability,
      implied_probability: p.impliedProbability,
      risk_level_estimated: risk,
      selections: p.selections.map((s) => ({
        match: `${s.home} – ${s.away}`,
        competition: s.competitionName,
        kickoff: s.kickoffAt.slice(0, 16).replace("T", " "),
        selection: outcomeLabel(s.key, s.home, s.away),
        odd: s.odd,
        model_probability: s.modelProbability,
        implied_probability: s.impliedProbability,
        edge: s.edge,
        reliability: s.reliability,
      })),
      note: "Probabilité combinée = produit des probabilités du modèle (matchs supposés indépendants).",
    };
  }

  private async summarize(fiche: unknown): Promise<{ summary: CouponSummary | null; ai: AiResult<CouponSummary> | null }> {
    if (this.settings["ai.coupon_summary"] === false) return { summary: null, ai: null };
    const { data: prompt } = await this.db.from("ai_prompts").select("system_prompt")
      .eq("key", "coupon_summary").eq("is_active", true).maybeSingle();
    if (!prompt) return { summary: null, ai: null };
    const { choices, pricing } = await loadAiSetup(this.db, (k) => env(k));
    const ai = await runValidated(fiche, prompt.system_prompt, choices, (raw) => validateCouponSummary(raw, fiche), pricing);
    if (ai.logs.length) {
      await this.db.from("ai_requests").insert(ai.logs.map((l) => ({
        user_id: null,
        kind: "coupon_summary",
        provider: l.provider,
        model: l.model,
        status: l.status,
        attempts: l.attempts,
        input_tokens: l.inputTokens,
        output_tokens: l.outputTokens,
        cost_usd: l.costUsd,
        latency_ms: l.latencyMs,
        error: l.error,
      })));
    }
    return { summary: ai.status === "ok" ? ai.value : null, ai };
  }

  private async saveCoupon(
    profile: Profile,
    criteria: Criteria,
    trigger: Trigger,
    slot: Slot | null,
    runId: number,
    p: ProposedCoupon,
    reasons: string[],
  ): Promise<boolean> {
    const thresholds = (this.settings["coupons.risk_thresholds"] ?? { prudent: 0.4, equilibre: 0.18 }) as RiskThresholds;
    const risk = riskLevel(p.combinedProbability, thresholds);
    const fiche = this.couponFiche(p, risk);
    const { summary: aiSummary, ai } = await this.summarize(fiche);
    const summary = aiSummary ?? defaultSummary(p);

    const firstKickoff = Date.parse(p.selections[0].kickoffAt);
    const latestAllowed = firstKickoff - criteria.min_minutes_before_kickoff * 60_000;
    const base = trigger === "schedule" && slot ? slot.slotAt.getTime() : this.now.getTime();
    const delay = trigger === "manual" ? 0 : profile.publish_delay_minutes * 60_000;
    const publishAt = new Date(Math.max(this.now.getTime(), Math.min(base + delay, latestAllowed)));
    const day = new Intl.DateTimeFormat("fr-FR", { timeZone: this.timeZone, weekday: "long", day: "numeric", month: "long" })
      .format(new Date(firstKickoff));

    const { data: coupon, error } = await this.db.from("coupons").insert({
      profile_id: profile.id,
      run_id: runId,
      category: profile.category,
      title: `${profile.name} · ${day}`,
      description: profile.description ?? "",
      risk_level: risk,
      total_odd: p.totalOdd,
      combined_probability: p.combinedProbability,
      implied_probability: p.impliedProbability,
      status: profile.publish_mode === "auto" ? "ready" : "pending_review",
      status_note: profile.publish_mode === "auto"
        ? `Généré (${trigger === "schedule" ? `créneau ${slot?.slotKey}` : trigger === "manual" ? "à la demande" : "génération continue"}), contrôle qualité réussi`
        : "Généré, en attente de validation humaine",
      publish_at: publishAt.toISOString(),
      first_kickoff_at: p.selections[0].kickoffAt,
      last_kickoff_at: p.selections.at(-1)!.kickoffAt,
      engine_version: ENGINE_VERSION,
      analysis: {
        ...summary,
        source: aiSummary ? "ia" : "calcul",
        ai_provider: ai?.status === "ok" ? ai.provider : null,
        ai_model: ai?.status === "ok" ? ai.model : null,
        market_note: p.impliedProbability !== null
          ? `Probabilité combinée selon le marché (marges retirées) : ${pct(p.impliedProbability)}.`
          : null,
        engine_quality: this.quality,
      },
      fingerprint: p.fingerprint,
    }).select("id").single();
    if (error) {
      reasons.push(error.code === "23505" ? "Coupon identique déjà en circulation (doublon évité)." : `Enregistrement impossible : ${error.message}`);
      return false;
    }
    const { error: selError } = await this.db.from("coupon_selections").insert(p.selections.map((s, i) => ({
      coupon_id: coupon.id,
      position: i + 1,
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
      justification: s.justification,
    })));
    if (selError) {
      await this.db.from("coupons").delete().eq("id", coupon.id);
      reasons.push(`Sélections non enregistrées : ${selError.message}`);
      return false;
    }
    return true;
  }

  // -------------------------------------------------------------------------
  /** Aperçu sans écriture : ce que le profil produirait maintenant. */
  async preview(profile: Profile) {
    const criteria = parseCriteria(profile.criteria);
    const load = await this.candidates(criteria.window_hours);
    const { kept, excluded } = filterCandidates(
      load.candidates,
      criteria,
      this.now,
      this.quality?.beatsBaseline ?? null,
      this.quality?.competitions ?? {},
    );
    const proposals = buildCoupons(kept, criteria, await liveFingerprints(this.db));
    return {
      profile: profile.key,
      candidates: load.candidates.length,
      kept: kept.length,
      excluded,
      coupons: proposals.map((p) => ({
        total_odd: p.totalOdd,
        combined_probability: p.combinedProbability,
        implied_probability: p.impliedProbability,
        selections: p.selections.map((x) => ({
          match: `${x.home} – ${x.away}`,
          competition: x.competitionName,
          selection: outcomeLabel(x.key, x.home, x.away),
          odd: x.odd,
          model: x.modelProbability,
          market: x.impliedProbability,
          edge: x.edge,
          reliability: x.reliability,
        })),
      })),
    };
  }

  // -------------------------------------------------------------------------
  /** Publie les coupons prêts dont l'heure est venue ; expire ceux devenus impossibles. */
  async publishDue(): Promise<{ published: number; expired: number }> {
    let published = 0;
    let expired = 0;
    const nowIso = this.now.toISOString();
    const { data: due, error } = await this.db.from("coupons")
      .select("id, coupon_selections(match_id, selection_key)").eq("status", "ready").lte("publish_at", nowIso).limit(50);
    if (error) throw new Error(error.message);
    for (const c of due ?? []) {
      const sels = (c.coupon_selections ?? []) as { match_id: number; selection_key: string }[];
      const live = await loadLiveChecks(this.db, sels.map((s) => ({ matchId: s.match_id, key: s.selection_key })));
      const problems = sels.flatMap((s) => {
        const l = live.get(`${s.match_id}:${s.selection_key}`);
        if (!l?.matchExists) return ["match introuvable"];
        if (l.status !== "scheduled") return [`match ${l.status}`];
        if (!l.kickoffAt || Date.parse(l.kickoffAt) <= this.now.getTime()) return ["match déjà commencé"];
        return [];
      });
      if (problems.length) {
        await this.db.from("coupons").update({ status: "expired", status_note: `Non publié : ${problems.join(", ")}` }).eq("id", c.id);
        expired++;
      } else {
        await this.db.from("coupons").update({
          status: "published",
          published_at: nowIso,
          status_note: "Publié automatiquement après un dernier contrôle",
        }).eq("id", c.id);
        published++;
      }
    }
    const { data: stale } = await this.db.from("coupons").update({
      status: "expired",
      status_note: "Non validé avant le coup d'envoi",
    }).eq("status", "pending_review").lte("first_kickoff_at", nowIso).select("id");
    expired += stale?.length ?? 0;
    return { published, expired };
  }

  async profiles(): Promise<Profile[]> {
    const { data, error } = await this.db.from("coupon_profiles").select("*").eq("is_active", true).order("sort");
    if (error) throw new Error(error.message);
    return (data ?? []) as Profile[];
  }

  async flags(): Promise<Record<string, boolean>> {
    const { data } = await this.db.from("feature_flags").select("key, enabled")
      .in("key", ["auto_generation_scheduled", "auto_generation_continuous"]);
    return Object.fromEntries((data ?? []).map((f) => [f.key, f.enabled] as [string, boolean]));
  }

  async tick() {
    const runs: RunSummary[] = [];
    const flags = await this.flags();
    for (const profile of await this.profiles()) {
      if (profile.mode === "scheduled" && flags.auto_generation_scheduled) {
        for (const slot of dueSlots(profile.generate_times, this.now, this.timeZone)) {
          const r = await this.generate(profile, "schedule", slot, null);
          if (r) runs.push(r);
        }
      } else if (profile.mode === "continuous" && flags.auto_generation_continuous) {
        const { data: last } = await this.db.from("generation_runs").select("started_at").eq("profile_id", profile.id)
          .order("started_at", { ascending: false }).limit(1).maybeSingle();
        const lastAt = last ? Date.parse(last.started_at) : 0;
        if (this.now.getTime() - lastAt < profile.continuous_min_interval_minutes * 60_000) continue;
        // Détection de changement : de nouvelles cotes depuis la dernière génération.
        const { data: fresh } = await this.db.from("odds_snapshots").select("captured_at")
          .gt("captured_at", new Date(lastAt).toISOString()).limit(1).maybeSingle();
        if (!fresh) continue;
        const r = await this.generate(profile, "continuous", null, null);
        if (r) runs.push(r);
      }
    }
    const publication = await this.publishDue();
    return { runs, ...publication };
  }
}

function runInBackground(task: Promise<unknown>): void {
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) runtime.waitUntil(task);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);

  const cronSecret = env("CRON_SECRET");
  const header = req.headers.get("x-cron-secret");
  const fromCron = Boolean(cronSecret && header && safeEqual(header, cronSecret));
  const caller = fromCron ? null : await callerFrom(req, ctx);
  if (!fromCron && !caller) return json({ error: "unauthorized" }, 401);
  if (caller && !caller.permissions.includes("generation.manage")) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const job = String(body?.job ?? "tick");
  const engine = new CouponEngine(ctx.db, new Date());

  try {
    if (job === "tick") {
      if (fromCron) {
        runInBackground(engine.init().then(() => engine.tick()).catch((e) => console.error("coupon-engine tick", e)));
        return json({ accepted: true }, 202);
      }
      await engine.init();
      return json(await engine.tick());
    }
    if (job === "generate") {
      const profileId = Number(body?.profile_id);
      const { data: profile } = await ctx.db.from("coupon_profiles").select("*").eq("id", profileId).maybeSingle();
      if (!profile) return json({ error: "profile_not_found" }, 404);
      await engine.init();
      const run = await engine.generate(profile as Profile, "manual", null, caller?.id ?? null);
      const publication = await engine.publishDue();
      await ctx.db.from("audit_logs").insert({
        actor_id: caller?.id ?? null,
        action: "coupons.generate",
        target_type: "coupon_profile",
        target_id: String(profileId),
        details: { status: run?.status, coupons: run?.coupons },
      });
      return json({ run, ...publication });
    }
    if (job === "preview") {
      const { data: profile } = await ctx.db.from("coupon_profiles").select("*").eq("id", Number(body?.profile_id)).maybeSingle();
      if (!profile) return json({ error: "profile_not_found" }, 404);
      await engine.init();
      return json(await engine.preview(profile as Profile));
    }
    return json({ error: "unknown_job", allowed: ["tick", "generate", "preview"] }, 400);
  } catch (e) {
    console.error("coupon-engine", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
