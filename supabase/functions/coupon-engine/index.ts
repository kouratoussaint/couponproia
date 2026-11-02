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
import { withLanguage } from "../_shared/ai/language.ts";
import { type CouponSummary, validateCouponSummary } from "../_shared/ai/validate.ts";
import {
  type CandidateLoad,
  liveFingerprints,
  liveMatchUsage,
  loadCandidates,
  loadLiveChecks,
} from "../_shared/coupons/data.ts";
import {
  blendWithMarket,
  buildCoupons,
  type Candidate,
  type Criteria,
  dailyLimit,
  defaultSummary,
  diversify,
  filterCandidates,
  outcomeLabel,
  outcomeLabelEn,
  parseCriteria,
  propose,
  type ProposedCoupon,
  qualityCheck,
  recordUsage,
  riskLevel,
  type RiskThresholds,
} from "../_shared/coupons/generator.ts";
import { aiJustification, type AiPosition, aiPositionOf, contradictions } from "../_shared/coupons/ai_consistency.ts";
import { dueSlots, localDate, localDayBounds, type Slot } from "../_shared/coupons/schedule.ts";
import { freshAnalysis, generateMatchAnalysis, MATCH_COLUMNS, type MatchRow } from "../_shared/analysis/generate.ts";
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
  /** Position de l'IA par match (null = analyse sans pronostic ou indisponible). */
  private positions = new Map<number, AiPosition | null>();
  /** Analyses IA que ce passage peut encore lancer (Coupon du jour). */
  private aiBudget = 6;

  constructor(private readonly db: SupabaseClient, private readonly now: Date) {}

  async init() {
    this.settings = await readSettings(this.db, [
      "app.timezone",
      "coupons.risk_thresholds",
      "coupons.max_publications_per_day",
      "coupons.data_freshness_hours",
      "ai.coupon_summary",
      "ai.analysis_ttl_hours",
      "featured.prepare_from_hour",
      "featured.auto_pick_hour",
      "coupons.market_weight",
      "coupons.max_match_uses",
    ]);
    this.quality = await loadEngineQuality(this.db);
  }

  get timeZone() {
    return String(this.settings["app.timezone"] ?? "Africa/Ouagadougou");
  }

  /** Part du marché dans la probabilité retenue (0 = modèle seul). */
  get marketWeight() {
    const w = Number(this.settings["coupons.market_weight"] ?? 0.7);
    return Number.isFinite(w) ? Math.min(1, Math.max(0, w)) : 0.7;
  }

  /** Nombre maximal de coupons en circulation contenant un même match (0 = sans limite). */
  get maxMatchUses() {
    const n = Number(this.settings["coupons.max_match_uses"] ?? 2);
    return Number.isFinite(n) ? Math.max(0, Math.round(n)) : 2;
  }

  private candidates(windowHours: number) {
    const w = Math.ceil(windowHours);
    if (!this.candidateCache.has(w)) {
      this.candidateCache.set(
        w,
        loadCandidates(this.db, this.now, w, this.quality).then((load) => ({
          ...load,
          candidates: blendWithMarket(load.candidates, this.marketWeight),
        })),
      );
    }
    return this.candidateCache.get(w)!;
  }

  // -------------------------------------------------------------------------
  /** Positions de l'IA déjà connues (analyses récentes), sans nouvel appel à l'IA. */
  async knownPositions(matchIds: number[]): Promise<Map<number, AiPosition | null>> {
    const out = new Map<number, AiPosition | null>();
    const missing = matchIds.filter((id) => {
      if (this.positions.has(id)) out.set(id, this.positions.get(id)!);
      return !this.positions.has(id);
    });
    const ttl = Number(this.settings["ai.analysis_ttl_hours"] ?? 12);
    const since = new Date(this.now.getTime() - Math.max(ttl, 24) * 3600_000).toISOString();
    for (let i = 0; i < missing.length; i += 100) {
      const { data, error } = await this.db.from("match_analyses").select("match_id, analysis, created_at")
        .in("match_id", missing.slice(i, i + 100)).eq("status", "ok").gte("created_at", since)
        .order("created_at", { ascending: false });
      if (error) throw new Error(error.message);
      for (const r of data ?? []) {
        if (out.has(r.match_id)) continue;
        const pos = aiPositionOf(r.analysis);
        out.set(r.match_id, pos);
        this.positions.set(r.match_id, pos);
      }
    }
    return out;
  }

  /** Position de l'IA, en lançant l'analyse si besoin (budget limité). null = pas de pronostic exploitable. */
  async ensurePosition(matchId: number): Promise<AiPosition | null> {
    const known = await this.knownPositions([matchId]);
    if (known.has(matchId)) return known.get(matchId) ?? null;
    if (this.aiBudget <= 0) return null;
    const { data: flag } = await this.db.from("feature_flags").select("enabled").eq("key", "match_analysis").maybeSingle();
    if (!flag?.enabled) return null;
    const { data: row } = await this.db.from("matches").select(MATCH_COLUMNS).eq("id", matchId).maybeSingle();
    const m = row as unknown as MatchRow | null;
    if (!m || !m.competition || !m.home || !m.away) return null;
    const { data: prompt } = await this.db.from("ai_prompts").select("key, version, system_prompt")
      .eq("key", "match_analysis").eq("is_active", true).maybeSingle();
    if (!prompt) return null;
    this.aiBudget--;
    const saved = await generateMatchAnalysis(this.db, m, prompt, null);
    const pos = saved.status === "ok" ? aiPositionOf(saved.analysis) : null;
    this.positions.set(matchId, pos);
    return pos;
  }

  /**
   * Coupon du jour : chaque match retenu passe par l'analyse IA. Un match sans pronostic de l'IA est
   * écarté ; une sélection qui contredit le pronostic est remplacée. Jusqu'à 4 recherches.
   */
  private async aiGatedProposals(
    kept: Candidate[],
    criteria: Criteria,
    taken: Set<string>,
    reasons: string[],
    details: Record<string, unknown>,
  ): Promise<ProposedCoupon[]> {
    let pool = [...kept];
    const noReco = new Set<number>();
    let replaced = 0;
    for (let round = 0; round < 4; round++) {
      if (new Set(pool.map((c) => c.matchId)).size < criteria.min_selections) break;
      const proposals = buildCoupons(pool, criteria, new Set(taken));
      if (!proposals.length) break;
      let clean = true;
      for (const sel of proposals.flatMap((p) => p.selections)) {
        const pos = await this.ensurePosition(sel.matchId);
        if (!pos?.recommendation) {
          noReco.add(sel.matchId);
          pool = pool.filter((c) => c.matchId !== sel.matchId);
          clean = false;
        } else if (contradictions(sel.key, pos).length) {
          pool = pool.filter((c) => c.matchId !== sel.matchId || contradictions(c.key, pos).length === 0);
          replaced++;
          clean = false;
        }
      }
      if (clean) {
        details.ai_gate = { analysed: [...this.positions.keys()].length, no_recommendation: noReco.size, replaced };
        return proposals;
      }
    }
    details.ai_gate = { analysed: [...this.positions.keys()].length, no_recommendation: noReco.size, replaced, failed: true };
    reasons.push(
      `Coupon du jour : pas assez de matchs avec un pronostic de l'IA cohérent (${noReco.size} sans pronostic, ${replaced} sélection(s) contraire(s) écartée(s), analyses restantes : ${this.aiBudget}).`,
    );
    return [];
  }

  /** Justification de chaque sélection : l'explication de l'IA quand elle existe, puis les chiffres. */
  private withAiJustifications(p: ProposedCoupon): ProposedCoupon {
    return {
      ...p,
      selections: p.selections.map((s) => ({
        ...s,
        justification: aiJustification(s.key, this.positions.get(s.matchId) ?? null, s.justification),
      })),
    };
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
    const filtered = filterCandidates(
      load.candidates,
      criteria,
      this.now,
      this.quality?.beatsBaseline ?? null,
      this.quality?.competitions ?? {},
    );
    const usage = await liveMatchUsage(this.db);
    const diverse = diversify(filtered.kept, usage, profile.category, this.maxMatchUses);
    // Cohérence avec les analyses IA déjà réalisées (tous les coupons, sans nouvel appel à l'IA).
    const known = await this.knownPositions([...new Set(diverse.kept.map((c) => c.matchId))]);
    const aiExcluded: Record<string, number> = {};
    const kept = diverse.kept.filter((c) => {
      const bad = contradictions(c.key, known.get(c.matchId) ?? null).length > 0;
      if (bad) aiExcluded["contraire au pronostic de l'IA"] = (aiExcluded["contraire au pronostic de l'IA"] ?? 0) + 1;
      return !bad;
    });
    const excluded = { ...filtered.excluded, ...diverse.excluded, ...aiExcluded };
    details.excluded = excluded;
    details.kept = kept.length;
    details.market_weight = this.marketWeight;
    if (new Set(kept.map((c) => c.matchId)).size < criteria.min_selections) {
      const top = Object.entries(excluded).sort((a, b) => b[1] - a[1]).slice(0, 3)
        .map(([why, n]) => `${why} (${n})`).join(", ");
      reasons.push(
        `Pas assez de sélections conformes aux critères : ${new Set(kept.map((c) => c.matchId)).size} match(s) sur ${criteria.min_selections} requis. Principaux motifs : ${top || "aucun"}.`,
      );
      return 0;
    }

    const taken = await liveFingerprints(this.db);
    // Coupon du jour : passage obligatoire par l'analyse IA de chaque match.
    const requireAi = profile.category === "du_jour";
    const proposals = (requireAi
      ? await this.aiGatedProposals(kept, criteria, taken, reasons, details)
      : buildCoupons(kept, criteria, taken)).map((p) => this.withAiJustifications(p));
    if (requireAi && proposals.length === 0) return 0;
    if (proposals.length === 0) {
      reasons.push(
        `Aucune combinaison de ${criteria.min_selections} à ${criteria.max_selections} sélections avec une cote totale entre ${dec(criteria.min_total_odd)} et ${dec(criteria.max_total_odd)}.`,
      );
      return 0;
    }

    let created = 0;
    const perDay = dailyLimit(profile.category, criteria);
    for (const proposal of proposals) {
      if (perDay > 0) {
        const first = proposal.selections.reduce((a, s) => (s.kickoffAt < a ? s.kickoffAt : a), proposal.selections[0].kickoffAt);
        const day = localDate(new Date(first), this.timeZone);
        const { start, end } = localDayBounds(day, this.timeZone);
        const { count: sameDay } = await this.db.from("coupons").select("id", { count: "exact", head: true })
          .eq("category", profile.category).in("status", ["pending_review", "ready", "published"])
          .gte("first_kickoff_at", start.toISOString()).lt("first_kickoff_at", end.toISOString());
        if ((sameDay ?? 0) >= perDay) {
          reasons.push(`« ${profile.name} » déjà en circulation pour le ${day} (${sameDay} sur ${perDay} autorisé${perDay > 1 ? "s" : ""}) : aucun autre n'est créé.`);
          continue;
        }
      }
      if (diversify(proposal.selections, usage, profile.category, this.maxMatchUses).kept.length !== proposal.selections.length) {
        reasons.push("Coupon écarté : un de ses matchs figure déjà dans assez de coupons en circulation.");
        continue;
      }
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
        recordUsage(usage, proposal.selections, profile.category);
      }
    }
    return created;
  }

  private couponFiche(p: ProposedCoupon, risk: string, lang: "fr" | "en" = "fr") {
    const en = lang === "en";
    return {
      total_odd: p.totalOdd,
      combined_probability: p.combinedProbability,
      implied_probability: p.impliedProbability,
      risk_level_estimated: risk,
      selections: p.selections.map((s) => ({
        match: `${s.home} – ${s.away}`,
        competition: s.competitionName,
        kickoff: s.kickoffAt.slice(0, 16).replace("T", " "),
        selection: en ? outcomeLabelEn(s.key, s.home, s.away) : outcomeLabel(s.key, s.home, s.away),
        odd: s.odd,
        model_probability: s.modelProbability,
        implied_probability: s.impliedProbability,
        edge: s.edge,
        reliability: s.reliability,
      })),
      note: en
        ? "Probability of each selection = retained estimate (blend of model and market). Combined probability = product of these estimates (matches assumed independent)."
        : "Probabilité de chaque sélection = estimation retenue (mélange du modèle et du marché). Probabilité combinée = produit de ces estimations (matchs supposés indépendants).",
    };
  }

  /** Résumé anglais du coupon (IA, sinon calcul), rangé dans analysis.en : écrit à la création. */
  private async englishAnalysis(p: ProposedCoupon, risk: string) {
    const { summary } = await this.summarize(this.couponFiche(p, risk, "en"), "en");
    const s = summary ?? defaultSummary(p, "en");
    return {
      ...s,
      market_note: p.impliedProbability !== null
        ? `Combined probability according to the market (margins removed): ${Math.round(p.impliedProbability * 100)}%.`
        : null,
    };
  }

  private async summarize(
    fiche: unknown,
    lang: "fr" | "en" = "fr",
  ): Promise<{ summary: CouponSummary | null; ai: AiResult<CouponSummary> | null }> {
    if (this.settings["ai.coupon_summary"] === false) return { summary: null, ai: null };
    const { data: prompt } = await this.db.from("ai_prompts").select("system_prompt")
      .eq("key", "coupon_summary").eq("is_active", true).maybeSingle();
    if (!prompt) return { summary: null, ai: null };
    const { choices, pricing } = await loadAiSetup(this.db, (k) => env(k));
    const ai = await runValidated(fiche, withLanguage(prompt.system_prompt, lang), choices, (raw) => validateCouponSummary(raw, fiche), pricing);
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
        quota: l.quota ?? null,
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
    const [{ summary: aiSummary, ai }, english] = await Promise.all([this.summarize(fiche), this.englishAnalysis(p, risk)]);
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
        en: english,
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
      justification_en: s.justificationEn ?? null,
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
    const filtered = filterCandidates(
      load.candidates,
      criteria,
      this.now,
      this.quality?.beatsBaseline ?? null,
      this.quality?.competitions ?? {},
    );
    const diverse = diversify(filtered.kept, await liveMatchUsage(this.db), profile.category, this.maxMatchUses);
    const kept = diverse.kept;
    const excluded = { ...filtered.excluded, ...diverse.excluded };
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
          model_alone: x.rawModelProbability ?? x.modelProbability,
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
      .select("id, ai_override, coupon_selections(match_id, selection_key)").eq("status", "ready").lte("publish_at", nowIso).limit(50);
    if (error) throw new Error(error.message);
    for (const c of due ?? []) {
      const sels = (c.coupon_selections ?? []) as { match_id: number; selection_key: string }[];
      const problems = await this.liveProblems(sels);
      const aiProblems = problems.length || c.ai_override ? [] : await this.aiProblems(sels);
      if (aiProblems.length) {
        await this.db.from("coupons").update({
          status: "pending_review",
          status_note: `À revoir avant publication : ${aiProblems.join(" ; ")}. Modifiez la sélection ou validez le coupon.`,
        }).eq("id", c.id);
        continue;
      }
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

  /** Dernier contrôle avant publication : chaque match existe, n'a pas commencé et reste programmé. */
  private async liveProblems(sels: { match_id: number; selection_key: string }[]): Promise<string[]> {
    const live = await loadLiveChecks(this.db, sels.map((s) => ({ matchId: s.match_id, key: s.selection_key })));
    return sels.flatMap((s) => {
      const l = live.get(`${s.match_id}:${s.selection_key}`);
      if (!l?.matchExists) return ["match introuvable"];
      if (l.status !== "scheduled") return [`match ${l.status}`];
      if (!l.kickoffAt || Date.parse(l.kickoffAt) <= this.now.getTime()) return ["match déjà commencé"];
      return [];
    });
  }

  /** Sélections qui contredisent une analyse IA connue de leur match. */
  private async aiProblems(sels: { match_id: number; selection_key: string }[]): Promise<string[]> {
    const known = await this.knownPositions([...new Set(sels.map((s) => s.match_id))]);
    const { data: teams } = await this.db.from("matches").select("id, home:teams!matches_home_team_fk(name), away:teams!matches_away_team_fk(name)")
      .in("id", [...new Set(sels.map((s) => s.match_id))]);
    const names = new Map((teams ?? []).map((t) => {
      const r = t as unknown as { id: number; home: { name: string } | null; away: { name: string } | null };
      return [r.id, [r.home?.name ?? "?", r.away?.name ?? "?"] as const];
    }));
    return sels.flatMap((s) => {
      const pos = known.get(s.match_id) ?? null;
      const bad = contradictions(s.selection_key, pos);
      if (!bad.length) return [];
      const [h, a] = names.get(s.match_id) ?? ["?", "?"];
      return [`« ${outcomeLabel(s.selection_key, h, a)} » contredit le pronostic de l'IA « ${outcomeLabel(bad[0], h, a)} » (${h} – ${a})`];
    });
  }

  /**
   * Modification d'un coupon généré, avant publication (super administrateur) : sélections
   * remplacées, cotes et probabilités recalculées sur les données du moment.
   */
  async editCoupon(
    couponId: string,
    wanted: { match_id: number; key: string }[],
    opts: { title?: string | null; note: string; force: boolean; actorId: string },
  ): Promise<{ ok: true; id: string } | { ok: false; status: number; error: string; message: string; items?: string[] }> {
    const { data: c } = await this.db.from("coupons")
      .select("id, status, title, profile_id, publish_at, analysis, coupon_selections(match_id, selection_key)")
      .eq("id", couponId).maybeSingle();
    if (!c) return { ok: false, status: 404, error: "not_found", message: "Coupon introuvable." };
    if (!["pending_review", "ready"].includes(c.status)) {
      return { ok: false, status: 409, error: "not_editable", message: "Seul un coupon à valider ou programmé se modifie : un coupon publié est immuable." };
    }
    const r = await this.selectionsFor(wanted);
    if (!r.ok) return { ok: false, status: 409, error: "invalid_selection", message: r.message };
    const proposal = propose(r.selections);
    const ai = await this.aiProblems(proposal.selections.map((s) => ({ match_id: s.matchId, selection_key: s.key })));
    if (ai.length && !opts.force) {
      return { ok: false, status: 409, error: "ai_contradiction", message: "Une sélection contredit l'analyse IA du match.", items: ai };
    }
    const saved = await this.writeSelections(c.id, proposal, {
      title: opts.title?.trim() || c.title,
      statusNote: `Modifié par l'équipe : ${opts.note}${ai.length ? " (malgré l'analyse IA)" : ""}`,
      aiOverride: ai.length > 0,
      publishAt: c.publish_at,
      previousAnalysis: c.analysis as Record<string, unknown> | null,
    });
    if (!saved.ok) return { ok: false, status: 409, error: "save_failed", message: saved.message };
    await this.db.from("audit_logs").insert({
      actor_id: opts.actorId, action: "coupon.edit", target_type: "coupon", target_id: c.id,
      details: {
        note: opts.note,
        forced_against_ai: ai.length > 0 ? ai : null,
        before: (c.coupon_selections ?? []).map((x: { match_id: number; selection_key: string }) => `${x.match_id}:${x.selection_key}`),
        after: proposal.selections.map((x) => `${x.matchId}:${x.key}`),
      },
    });
    return { ok: true, id: c.id };
  }

  /** Copie d'un coupon retiré, à modifier puis à publier (correction). Matchs déjà commencés écartés. */
  async duplicateCoupon(couponId: string, actorId: string): Promise<{ ok: true; id: string } | { ok: false; message: string }> {
    const { data: c } = await this.db.from("coupons")
      .select("id, status, title, description, category, profile_id, coupon_selections(match_id, selection_key)")
      .eq("id", couponId).maybeSingle();
    if (!c) return { ok: false, message: "Coupon introuvable." };
    if (c.status !== "withdrawn") return { ok: false, message: "Retirez d'abord le coupon : seul un coupon retiré se duplique." };
    const sels = (c.coupon_selections ?? []) as { match_id: number; selection_key: string }[];
    const r = await this.selectionsFor(sels.map((s) => ({ match_id: s.match_id, key: s.selection_key })), true);
    if (!r.ok) return { ok: false, message: r.message };
    const proposal = propose(r.selections);
    const { data: copy, error } = await this.db.from("coupons").insert({
      profile_id: c.profile_id,
      category: c.category,
      title: c.title,
      description: c.description ?? "",
      risk_level: "equilibre",
      total_odd: proposal.totalOdd,
      combined_probability: proposal.combinedProbability,
      implied_probability: proposal.impliedProbability,
      status: "pending_review",
      status_note: "Correction d'un coupon retiré, à modifier puis à valider",
      publish_at: this.now.toISOString(),
      first_kickoff_at: proposal.selections[0].kickoffAt,
      last_kickoff_at: proposal.selections.at(-1)!.kickoffAt,
      engine_version: ENGINE_VERSION,
      analysis: {},
      fingerprint: proposal.fingerprint,
    }).select("id").single();
    if (error) return { ok: false, message: error.code === "23505" ? "Un coupon identique est déjà en circulation." : error.message };
    const saved = await this.writeSelections(copy.id, proposal, {
      title: c.title, statusNote: "Correction d'un coupon retiré, à modifier puis à valider", aiOverride: false,
      publishAt: this.now.toISOString(), previousAnalysis: null,
    });
    if (!saved.ok) {
      await this.db.from("coupons").delete().eq("id", copy.id);
      return { ok: false, message: saved.message };
    }
    await this.db.from("audit_logs").insert({
      actor_id: actorId, action: "coupon.duplicate", target_type: "coupon", target_id: copy.id, details: { from: c.id },
    });
    return { ok: true, id: copy.id };
  }

  /** Sélections demandées, relues dans les données du moment (cote médiane, probabilité retenue). */
  private async selectionsFor(
    wanted: { match_id: number; key: string }[],
    skipUnavailable = false,
  ): Promise<{ ok: true; selections: Candidate[] } | { ok: false; message: string }> {
    if (wanted.length < 1 || wanted.length > 10) return { ok: false, message: "Entre 1 et 10 sélections." };
    if (new Set(wanted.map((w) => w.match_id)).size !== wanted.length) return { ok: false, message: "Un seul pari par match." };
    const load = await this.candidates(96);
    const limit = this.now.getTime() + 30 * 60_000;
    const selections: Candidate[] = [];
    const missing: string[] = [];
    for (const w of wanted) {
      const cand = load.candidates.find((c) => c.matchId === Number(w.match_id) && c.key === w.key);
      if (!cand || Date.parse(cand.kickoffAt) <= limit) missing.push(`${w.match_id}:${w.key}`);
      else selections.push(cand);
    }
    if (missing.length && !skipUnavailable) {
      return { ok: false, message: `Cote indisponible ou match à moins de 30 minutes du coup d'envoi : ${missing.join(", ")}.` };
    }
    if (!selections.length) return { ok: false, message: "Aucune sélection encore jouable." };
    return { ok: true, selections };
  }

  /** Enregistre les sélections d'un coupon et ses totaux (résumé recalculé). */
  private async writeSelections(
    couponId: string,
    proposal: ProposedCoupon,
    o: { title: string; statusNote: string; aiOverride: boolean; publishAt: string; previousAnalysis: Record<string, unknown> | null },
  ): Promise<{ ok: true } | { ok: false; message: string }> {
    await this.knownPositions([...new Set(proposal.selections.map((s) => s.matchId))]);
    const p = this.withAiJustifications(proposal);
    const thresholds = (this.settings["coupons.risk_thresholds"] ?? { prudent: 0.4, equilibre: 0.18 }) as RiskThresholds;
    const risk = riskLevel(p.combinedProbability, thresholds);
    const [{ summary: aiSummary }, english] = await Promise.all([
      this.summarize(this.couponFiche(p, risk)),
      this.englishAnalysis(p, risk),
    ]);
    const summary = aiSummary ?? defaultSummary(p);
    const latest = Date.parse(p.selections[0].kickoffAt) - 30 * 60_000;
    const { error } = await this.db.from("coupons").update({
      title: o.title,
      risk_level: risk,
      total_odd: p.totalOdd,
      combined_probability: p.combinedProbability,
      implied_probability: p.impliedProbability,
      first_kickoff_at: p.selections[0].kickoffAt,
      last_kickoff_at: p.selections.at(-1)!.kickoffAt,
      publish_at: new Date(Math.max(this.now.getTime(), Math.min(Date.parse(o.publishAt), latest))).toISOString(),
      fingerprint: p.fingerprint,
      status_note: o.statusNote,
      ai_override: o.aiOverride,
      analysis: {
        ...(o.previousAnalysis ?? {}),
        ...summary,
        source: aiSummary ? "ia" : "calcul",
        market_note: p.impliedProbability !== null
          ? `Probabilité combinée selon le marché (marges retirées) : ${pct(p.impliedProbability)}.`
          : null,
        en: english,
        edited: true,
      },
    }).eq("id", couponId);
    if (error) return { ok: false, message: error.code === "23505" ? "Un coupon identique est déjà en circulation." : error.message };
    await this.db.from("coupon_selections").delete().eq("coupon_id", couponId);
    const { error: selError } = await this.db.from("coupon_selections").insert(p.selections.map((s, i) => ({
      coupon_id: couponId,
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
      justification_en: s.justificationEn ?? null,
    })));
    if (selError) return { ok: false, message: `Sélections non enregistrées : ${selError.message}` };
    return { ok: true };
  }

  /** Publication immédiate d'un coupon prêt (programmé) ou à valider, avant son heure. */
  async publishNow(couponId: string, actorId: string, force = false): Promise<{ ok: true } | { ok: false; reason: string; ai?: string[] }> {
    const { data: c } = await this.db.from("coupons")
      .select("id, status, coupon_selections(match_id, selection_key)").eq("id", couponId).maybeSingle();
    if (!c) return { ok: false, reason: "Coupon introuvable." };
    if (!["ready", "pending_review"].includes(c.status)) {
      return { ok: false, reason: `Ce coupon n'est ni programmé ni à valider (${c.status}).` };
    }
    const problems = await this.liveProblems((c.coupon_selections ?? []) as { match_id: number; selection_key: string }[]);
    if (problems.length) return { ok: false, reason: `Publication impossible : ${[...new Set(problems)].join(", ")}.` };
    const ai = await this.aiProblems((c.coupon_selections ?? []) as { match_id: number; selection_key: string }[]);
    if (ai.length && !force) return { ok: false, reason: `${ai.join(" ; ")}.`, ai };
    const nowIso = this.now.toISOString();
    const { data: updated } = await this.db.from("coupons").update({
      status: "published",
      published_at: nowIso,
      publish_at: nowIso,
      status_note: c.status === "pending_review"
        ? "Validé et publié avant l'heure prévue par un administrateur"
        : "Publié avant l'heure prévue par un administrateur",
      ai_override: ai.length > 0,
    }).eq("id", couponId).eq("status", c.status).select("id").maybeSingle();
    if (!updated) return { ok: false, reason: "Le coupon a changé entre-temps : actualisez." };
    await this.db.from("audit_logs").insert({
      actor_id: actorId, action: "coupon.publish_now", target_type: "coupon", target_id: couponId,
      details: { previous_status: c.status },
    });
    return { ok: true };
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
    const featured = await this.prepareFeatured().catch((e) => ({ error: String((e as Error).message ?? e) }));
    return { runs, ...publication, featured };
  }

  /** Analyse offerte du jour : match choisi le matin, analyse préparée pour qu'elle soit prête. */
  async prepareFeatured() {
    const fromHour = Number(this.settings["featured.prepare_from_hour"] ?? 5);
    const localHour = Number(new Intl.DateTimeFormat("en-GB", { timeZone: this.timeZone, hour: "2-digit", hourCycle: "h23" })
      .format(this.now));
    if (localHour < fromHour) return { skipped: "too_early" };
    const { data: flag } = await this.db.from("feature_flags").select("enabled").eq("key", "match_analysis").maybeSingle();
    if (!flag?.enabled) return { skipped: "analysis_disabled" };
    // Choix du super administrateur s'il existe ; sinon choix automatique à partir de l'heure réglée.
    const today = localDate(this.now, this.timeZone);
    const { data: chosen } = await this.db.from("featured_matches").select("match_id").eq("day", today).maybeSingle();
    let matchId: number | null = chosen?.match_id ?? null;
    if (!matchId) {
      const autoHour = Number(this.settings["featured.auto_pick_hour"] ?? 9);
      if (localHour < autoHour) return { skipped: "waiting_for_choice", auto_pick_hour: autoHour };
      const { data: picked, error } = await this.db.rpc("svc_pick_featured_match");
      if (error) throw new Error(error.message);
      matchId = picked;
    }
    if (!matchId) return { skipped: "no_match" };
    const { data: row } = await this.db.from("matches").select(MATCH_COLUMNS).eq("id", matchId).maybeSingle();
    const m = row as unknown as MatchRow | null;
    if (!m || !m.competition || !m.home || !m.away) return { skipped: "match_incomplete" };
    const { data: prompt } = await this.db.from("ai_prompts").select("key, version, system_prompt")
      .eq("key", "match_analysis").eq("is_active", true).maybeSingle();
    const ttl = Number(this.settings["ai.analysis_ttl_hours"] ?? 12);
    if (await freshAnalysis(this.db, m, ttl, prompt?.version ?? null)) return { match_id: m.id, ready: true };
    const saved = await generateMatchAnalysis(this.db, m, prompt, null);
    return { match_id: m.id, prepared: saved.id };
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
    if (job === "publish_now") {
      if (!caller || !caller.permissions.includes("coupons.publish")) return json({ error: "forbidden" }, 403);
      await engine.init();
      const r = await engine.publishNow(String(body?.coupon_id ?? ""), caller.id, body?.force === true);
      return r.ok
        ? json({ ok: true })
        : json({ error: r.ai ? "ai_contradiction" : "not_publishable", message: r.reason, items: r.ai ?? null }, 409);
    }
    if (job === "edit_coupon" || job === "duplicate_coupon") {
      if (!caller || !caller.permissions.includes("coupons.edit")) return json({ error: "forbidden" }, 403);
      await engine.init();
      if (job === "duplicate_coupon") {
        const r = await engine.duplicateCoupon(String(body?.coupon_id ?? ""), caller.id);
        return r.ok ? json({ ok: true, id: r.id }) : json({ error: "not_duplicable", message: r.message }, 409);
      }
      const note = String(body?.note ?? "").trim();
      if (note.length < 3) return json({ error: "note_required", message: "Indiquez le motif de la modification." }, 400);
      const wanted = Array.isArray(body?.selections)
        ? (body.selections as { match_id: unknown; key: unknown }[]).map((x) => ({ match_id: Number(x.match_id), key: String(x.key) }))
        : [];
      const r = await engine.editCoupon(String(body?.coupon_id ?? ""), wanted, {
        title: typeof body?.title === "string" ? body.title.slice(0, 120) : null,
        note: note.slice(0, 200),
        force: body?.force === true,
        actorId: caller.id,
      });
      return r.ok ? json({ ok: true, id: r.id }) : json({ error: r.error, message: r.message, items: r.items ?? null }, r.status);
    }
    return json({ error: "unknown_job", allowed: ["tick", "generate", "preview", "publish_now", "edit_coupon", "duplicate_coupon"] }, 400);
  } catch (e) {
    console.error("coupon-engine", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
