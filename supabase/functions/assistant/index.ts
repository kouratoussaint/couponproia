// Edge Function : « Mon Assistant IA ».
//
// 1. L'IA comprend la demande (intention + critères, JSON vérifié).
// 2. Le moteur exécute : candidats réels, filtres, combinaison, contrôles (aucune cote ni
//    probabilité ne vient de l'IA).
// 3. Le résultat est enregistré (proposition de coupon, analyse) ; le crédit n'est débité
//    qu'après un résultat réussi, une seule fois (opération = identifiant du message).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { type AttemptLog, runValidated } from "../_shared/ai/analyst.ts";
import { loadAiSetup } from "../_shared/ai/setup.ts";
import { withLanguage } from "../_shared/ai/language.ts";
import { asLang, type Lang } from "../_shared/lang.ts";
import { FORBIDDEN, validateCouponSummary } from "../_shared/ai/validate.ts";
import { diagnoseCoupon, exclusionLabel, opportunities } from "../_shared/assistant/actions.ts";
import {
  criteriaFromIntent,
  dateRange,
  type Intent,
  matchNames,
  normalizeName,
  PAID_INTENTS,
  parseIntent,
} from "../_shared/assistant/intent.ts";
import { insertUserCoupon, loadUserCoupon, type StoredLine } from "../_shared/assistant/store.ts";
import { describeRequest, extractConstraints, reconcileIntent } from "../_shared/assistant/keywords.ts";
import { loadCandidates, loadLiveChecks } from "../_shared/coupons/data.ts";
import {
  buildCoupons,
  type Candidate,
  type Criteria,
  defaultSummary,
  filterCandidates,
  outcomeLabel,
  outcomeLabelEn,
  parseCriteria,
  type ProposedCoupon,
  riskLevel,
  type RiskThresholds,
} from "../_shared/coupons/generator.ts";
import { type EngineQuality, loadEngineQuality } from "../_shared/engine/quality.ts";
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";

const pctFr = (p: number) => `${Math.round(p * 100)} %`;
const decFr = (x: number) => x.toFixed(2).replace(".", ",");
const pctEn = (p: number) => `${Math.round(p * 100)}%`;
const decEn = (x: number) => x.toFixed(2);

interface Result {
  content: string;
  intent: string;
  coupons: ProposedCoupon[];
  criteria?: Criteria;
  payload: Record<string, unknown>;
  paid: boolean;
}


async function logAi(db: SupabaseClient, userId: string, kind: string, logs: AttemptLog[]) {
  if (!logs.length) return;
  await db.from("ai_requests").insert(logs.map((l) => ({
    user_id: userId,
    kind,
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

class Assistant {
  private settings: Record<string, unknown> = {};
  private quality: EngineQuality | null = null;
  readonly warnings: string[] = [];

  constructor(
    private readonly db: SupabaseClient,
    private readonly userId: string,
    private readonly now: Date,
    readonly lang: Lang = "fr",
  ) {}

  private get en() {
    return this.lang === "en";
  }
  /** Texte selon la langue de l'utilisateur. */
  private t(fr: string, en: string) {
    return this.en ? en : fr;
  }
  private pct(p: number) {
    return this.en ? pctEn(p) : pctFr(p);
  }
  private dec(x: number) {
    return this.en ? decEn(x) : decFr(x);
  }
  private label(key: string, home: string, away: string) {
    return this.en ? outcomeLabelEn(key, home, away) : outcomeLabel(key, home, away);
  }

  async init() {
    this.settings = await readSettings(this.db, [
      "app.timezone",
      "assistant.cost_per_action",
      "assistant.daily_message_limit",
      "coupons.risk_thresholds",
    ]);
    this.quality = await loadEngineQuality(this.db);
  }

  get timeZone() {
    return String(this.settings["app.timezone"] ?? "Africa/Ouagadougou");
  }
  get cost() {
    return Math.max(1, Number(this.settings["assistant.cost_per_action"] ?? 1));
  }
  get dailyLimit() {
    return Number(this.settings["assistant.daily_message_limit"] ?? 60);
  }

  async competitions() {
    const { data } = await this.db.from("competitions").select("id, name").eq("is_active", true).order("priority");
    return (data ?? []) as { id: number; name: string }[];
  }

  // ---------------------------------------------------------------------------
  async understand(message: string, history: { role: string; content: string }[], current: StoredLine[] | null) {
    const { data: prompt } = await this.db.from("ai_prompts").select("system_prompt")
      .eq("key", "assistant_intent").eq("is_active", true).maybeSingle();
    if (!prompt) return null;
    const { choices, pricing } = await loadAiSetup(this.db, (k) => env(k));
    const input = {
      message,
      historique: history.slice(-6).map((h) => ({ role: h.role, texte: h.content.slice(0, 300) })),
      coupon_en_cours: current
        ? current.map((l) => ({
          position: l.position,
          match: `${l.home} – ${l.away}`,
          selection: this.label(l.key, l.home, l.away),
          cote: l.odd,
        }))
        : null,
      competitions: (await this.competitions()).map((c) => c.name),
      date_du_jour: new Intl.DateTimeFormat(this.en ? "en-GB" : "fr-FR", { timeZone: this.timeZone, dateStyle: "full" })
        .format(this.now),
      date_iso: this.now.toISOString().slice(0, 10),
    };
    const res = await runValidated(input, withLanguage(prompt.system_prompt, this.lang), choices, (raw) => {
      const v = parseIntent(raw);
      if (!v.ok) return v;
      const bad = v.value.reponse.match(FORBIDDEN);
      return bad ? { ok: false, errors: [`Mot interdit dans « reponse » : « ${bad[0]} ».`] } : { ok: true, value: v.value };
    }, pricing);
    await logAi(this.db, this.userId, "assistant_intent", res.logs);
    if (res.status !== "ok") return this.fallbackIntent(message);
    // Les chiffres et mots-clés écrits par l'utilisateur priment sur la compréhension de l'IA.
    return reconcileIntent(res.value, message, this.now, this.timeZone).intent;
  }

  /** IA indisponible : une demande de coupon reste comprise grâce aux mots-clés et aux chiffres. */
  fallbackIntent(message: string): Intent | null {
    const x = extractConstraints(message, this.now, this.timeZone);
    const wantsCoupon = /\b(coupons?|tickets?|combines?|composer?|propose|fais|cree|creer|genere|make|build|create|give|slip|accumulator|acca)\b/
      .test(message.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase());
    if (!wantsCoupon) return null;
    return {
      intent: (x.nombre_coupons ?? 1) > 1 ? "variantes" : "creer_coupon",
      jour: x.jour,
      competitions: [],
      equipes: [],
      exclure_equipes: [],
      nombre_selections: x.nombre_selections,
      cote_totale_cible: x.cote_totale_cible,
      cote_totale_min: x.cote_totale_min,
      cote_totale_max: x.cote_totale_max,
      cote_selection_min: x.cote_selection_min,
      cote_selection_max: x.cote_selection_max,
      marches: x.marches,
      issues: x.issues,
      risque: x.risque,
      nombre_coupons: x.nombre_coupons,
      retirer_positions: [],
      remplacer_plus_fragiles: 0,
      ajouter: 0,
      reponse: "",
    };
  }

  // ---------------------------------------------------------------------------
  private async candidatesFor(i: Intent) {
    const range = dateRange(i.jour, this.now, this.timeZone, this.lang);
    const hours = Math.max(1, (range.until.getTime() - this.now.getTime()) / 3600_000);
    const load = await loadCandidates(this.db, this.now, hours, this.quality, range);
    let cands = load.candidates;
    if (i.competitions.length) {
      const { ids, unknown } = matchNames(i.competitions, await this.competitions());
      if (unknown.length) {
        this.warnings.push(this.t(`Compétition(s) non suivie(s) : ${unknown.join(", ")}.`, `Competition(s) not covered: ${unknown.join(", ")}.`));
      }
      if (ids.length) cands = cands.filter((c) => ids.includes(c.competitionId));
    }
    if (i.exclure_equipes.length) {
      const ex = i.exclure_equipes.map(normalizeName);
      cands = cands.filter((c) => !ex.some((e) => [c.home, c.away].some((t) => normalizeName(t).includes(e))));
    }
    return { cands, range, upcoming: load.upcomingMatches, withOdds: load.matchesWithOdds, hours };
  }

  /** Meilleure issue (selon les critères si possible) du match de chaque équipe demandée. */
  private fixedForTeams(i: Intent, all: Candidate[], kept: Candidate[]): Candidate[] {
    const fixed: Candidate[] = [];
    for (const team of i.equipes) {
      const t = normalizeName(team);
      const ofTeam = (c: Candidate) => [c.home, c.away].some((n) => normalizeName(n).includes(t));
      const pick = (list: Candidate[]) => list.filter(ofTeam).sort((a, b) => b.modelProbability - a.modelProbability)[0];
      const best = pick(kept) ?? pick(all.filter((c) => (c.edge ?? 0) <= 0.1));
      if (!best) {
        this.warnings.push(this.t(`Aucun match coté de « ${team} » sur la période.`, `No priced match for “${team}” in the period.`));
        continue;
      }
      if (!kept.includes(best)) {
        this.warnings.push(this.t(
          `${best.home} – ${best.away} ajouté à votre demande, hors critères habituels du moteur.`,
          `${best.home} – ${best.away} added at your request, outside the engine's usual criteria.`,
        ));
      }
      if (!fixed.some((f) => f.matchId === best.matchId)) fixed.push(best);
    }
    return fixed;
  }

  private build(cands: Candidate[], criteria: Criteria, fixed: Candidate[], keepTotals = false) {
    const { kept, excluded } = filterCandidates(
      cands,
      criteria,
      this.now,
      this.quality?.beatsBaseline ?? null,
      this.quality?.competitions ?? {},
    );
    let coupons = buildCoupons(kept, criteria, new Set(), 200_000, fixed);
    if (coupons.length === 0) {
      // Une seule tentative assouplie, signalée à l'utilisateur. Les cotes et le nombre de
      // sélections demandés explicitement ne sont jamais assouplis.
      const relaxed = parseCriteria({
        ...criteria,
        min_model_probability: Math.max(0.25, criteria.min_model_probability - 0.1),
        min_total_odd: keepTotals ? criteria.min_total_odd : criteria.min_total_odd * 0.9,
        max_total_odd: keepTotals ? criteria.max_total_odd : criteria.max_total_odd * 1.15,
        min_edge: Math.min(criteria.min_edge, -0.08),
      });
      const again = filterCandidates(cands, relaxed, this.now, this.quality?.beatsBaseline ?? null, this.quality?.competitions ?? {});
      coupons = buildCoupons(again.kept, relaxed, new Set(), 200_000, fixed);
      if (coupons.length) {
        this.warnings.push(keepTotals
          ? this.t("Seuil de probabilité légèrement assoupli pour respecter vos cotes.", "Probability threshold slightly relaxed to respect your odds.")
          : this.t("Critères légèrement assouplis pour trouver une combinaison.", "Criteria slightly relaxed to find a combination."));
      }
    }
    return { coupons, excluded, kept };
  }

  private noResult(why: string, excluded: Record<string, number>): Result {
    const top = Object.entries(excluded).sort((a, b) => b[1] - a[1]).slice(0, 3)
      .map(([w, n]) => `${exclusionLabel(w, this.lang)} (${n})`);
    return {
      content: this.en
        ? `${why}${top.length ? ` Main obstacles: ${top.join(", ")}.` : ""} Try another period, a different target odd or fewer selections. No credit was charged.`
        : `${why}${top.length ? ` Principaux obstacles : ${top.join(", ")}.` : ""} Essayez une autre période, une cote cible différente ou moins de sélections. Aucun crédit n'a été débité.`,
      intent: "aucun_resultat",
      coupons: [],
      payload: { excluded },
      paid: false,
    };
  }

  async create(i: Intent): Promise<Result> {
    const { cands, range, upcoming, withOdds, hours } = await this.candidatesFor(i);
    if (cands.length === 0) {
      return this.noResult(
        upcoming === 0
          ? this.t(`Aucun match programmé ${range.label} dans les compétitions suivies.`, `No match scheduled ${range.label} in the competitions covered.`)
          : this.t(
            `Pas de cotes disponibles ${range.label} pour les critères demandés (${withOdds} match(s) coté(s) sur ${upcoming}).`,
            `No odds available ${range.label} for the requested criteria (${withOdds} priced match(es) out of ${upcoming}).`,
          ),
        {},
      );
    }
    const { criteria, warnings } = criteriaFromIntent(i, hours, this.lang);
    this.warnings.push(...warnings);
    const { kept: preKept } = filterCandidates(cands, criteria, this.now, this.quality?.beatsBaseline ?? null, this.quality?.competitions ?? {});
    const fixed = this.fixedForTeams(i, cands, preKept);
    const explicitTotals = Boolean(i.cote_totale_cible || i.cote_totale_min || i.cote_totale_max);
    const { coupons, excluded } = this.build(cands, criteria, fixed, explicitTotals);
    const asked = describeRequest(i, range.label, this.lang);
    const dec = (x: number) => this.dec(x);
    const pct = (p: number) => this.pct(p);
    if (coupons.length === 0) {
      const n = criteria.min_selections === criteria.max_selections
        ? `${criteria.min_selections}`
        : `${criteria.min_selections} ${this.t("à", "to")} ${criteria.max_selections}`;
      return this.noResult(
        this.en
          ? `${asked} I found no combination of ${n} selections ${range.label} with a total odd between ${dec(criteria.min_total_odd)} and ${dec(criteria.max_total_odd)}.`
          : `${asked} Je n'ai pas trouvé de combinaison de ${n} sélections ${range.label} avec une cote totale entre ${dec(criteria.min_total_odd)} et ${dec(criteria.max_total_odd)}.`,
        excluded,
      );
    }
    const first = coupons[0];
    const market = first.impliedProbability !== null ? ` (${this.t("marché : ", "market: ")}${pct(first.impliedProbability)})` : "";
    const content = coupons.length > 1
      ? this.t(
        `Voici ${coupons.length} versions ${range.label}, cotes totales ${coupons.map((c) => dec(c.totalOdd)).join(", ")}. Comparez les probabilités estimées avant de choisir.`,
        `Here are ${coupons.length} versions ${range.label}, total odds ${coupons.map((c) => dec(c.totalOdd)).join(", ")}. Compare the estimated probabilities before choosing.`,
      )
      : this.t(
        `Voici un coupon de ${first.selections.length} sélections ${range.label} : cote totale ${dec(first.totalOdd)}, probabilité estimée par le modèle ${pct(first.combinedProbability)}${market}.`,
        `Here is a coupon of ${first.selections.length} selections ${range.label}: total odd ${dec(first.totalOdd)}, probability estimated by the model ${pct(first.combinedProbability)}${market}.`,
      );
    return { content: `${asked} ${content}`, intent: i.intent, coupons, criteria, payload: {}, paid: true };
  }

  async modify(i: Intent, current: StoredLine[] | null, currentCriteria: unknown): Promise<Result> {
    if (!current?.length) {
      return {
        content: this.t("Je n'ai pas de coupon en cours à modifier. Demandez-moi d'abord d'en créer un.", "I have no current coupon to modify. Ask me to create one first."),
        intent: "question",
        coupons: [],
        payload: {},
        paid: false,
      };
    }
    const base = parseCriteria(currentCriteria);
    const toRemove = new Set(i.retirer_positions);
    const replace = i.remplacer_plus_fragiles;
    if (replace > 0) {
      const { fragility } = await import("../_shared/assistant/actions.ts");
      [...current].filter((l) => !toRemove.has(l.position)).sort((a, b) => fragility(b) - fragility(a))
        .slice(0, replace).forEach((l) => toRemove.add(l.position));
    }
    const removedMatches = new Set(current.filter((l) => toRemove.has(l.position)).map((l) => l.matchId));
    const target = current.length - (replace > 0 ? 0 : toRemove.size) + i.ajouter;
    if (target < 1) {
      return {
        content: this.t("Le coupon serait vide : précisez quoi conserver.", "The coupon would be empty: say what to keep."),
        intent: "question",
        coupons: [],
        payload: {},
        paid: false,
      };
    }

    const hours = Math.max(1, (Math.max(...current.map((l) => Date.parse(l.kickoffAt))) - this.now.getTime()) / 3600_000 + 24);
    const load = await loadCandidates(this.db, this.now, Math.max(hours, base.window_hours), this.quality);
    const byKey = new Map(load.candidates.map((c) => [`${c.matchId}:${c.key}`, c] as [string, Candidate]));
    const kept: Candidate[] = [];
    for (const l of current) {
      if (toRemove.has(l.position)) continue;
      const fresh = byKey.get(`${l.matchId}:${l.key}`);
      if (fresh) kept.push(fresh);
      else {
        this.warnings.push(this.t(
          `${l.home} – ${l.away} retiré : match commencé ou issue plus cotée.`,
          `${l.home} – ${l.away} removed: match started or outcome no longer priced.`,
        ));
      }
    }
    if (kept.length >= target) {
      const p = this.toProposal(kept.slice(0, target));
      return { content: this.modifiedText(p, toRemove.size, 0), intent: i.intent, coupons: [p], criteria: base, payload: {}, paid: true };
    }
    const pool = load.candidates.filter((c) => !removedMatches.has(c.matchId));
    const keptOdd = kept.reduce((s, c) => s * c.odd, 1);
    const origOdd = current.reduce((s, l) => s * l.odd, 1);
    const criteria = parseCriteria({
      ...base,
      min_selections: target,
      max_selections: target,
      min_total_odd: Math.max(keptOdd * 1.01, (replace > 0 ? origOdd : base.min_total_odd) * 0.8),
      max_total_odd: Math.max(keptOdd * 1.5, (replace > 0 ? origOdd : base.max_total_odd) * 1.25),
      window_hours: Math.max(hours, base.window_hours),
    });
    const { coupons, excluded } = this.build(pool, criteria, kept);
    if (!coupons.length) return this.noResult(this.t("Je n'ai pas trouvé de remplaçant compatible.", "I found no compatible replacement."), excluded);
    return { content: this.modifiedText(coupons[0], toRemove.size, coupons[0].selections.length - kept.length), intent: i.intent, coupons: [coupons[0]], criteria, payload: {}, paid: true };
  }

  private modifiedText(p: ProposedCoupon, removed: number, added: number) {
    const parts = [];
    if (this.en) {
      if (removed) parts.push(`${removed} selection(s) removed`);
      if (added) parts.push(`${added} added`);
      return `Coupon modified (${parts.join(", ") || "odds updated"}): ${p.selections.length} selections, total odd ${this.dec(p.totalOdd)}, estimated probability ${this.pct(p.combinedProbability)}.`;
    }
    if (removed) parts.push(`${removed} sélection(s) retirée(s)`);
    if (added) parts.push(`${added} ajoutée(s)`);
    return `Coupon modifié (${parts.join(", ") || "cotes actualisées"}) : ${p.selections.length} sélections, cote totale ${this.dec(p.totalOdd)}, probabilité estimée ${this.pct(p.combinedProbability)}.`;
  }

  private toProposal(selections: Candidate[]): ProposedCoupon {
    const sorted = [...selections].sort((a, b) => a.kickoffAt.localeCompare(b.kickoffAt));
    const implied = sorted.every((s) => s.impliedProbability !== null)
      ? sorted.reduce((p, s) => p * (s.impliedProbability as number), 1)
      : null;
    return {
      selections: sorted,
      totalOdd: Math.round(sorted.reduce((p, s) => p * s.odd, 1) * 100) / 100,
      combinedProbability: Math.round(sorted.reduce((p, s) => p * s.modelProbability, 1) * 10000) / 10000,
      impliedProbability: implied === null ? null : Math.round(implied * 10000) / 10000,
      fingerprint: sorted.map((s) => `${s.matchId}:${s.key}`).sort().join("|"),
    };
  }

  async analyzeCoupon(current: StoredLine[] | null): Promise<Result> {
    if (!current?.length) {
      return {
        content: this.t(
          "Je n'ai pas de coupon à analyser dans cette conversation. Créez-en un ou ouvrez un de vos coupons.",
          "I have no coupon to analyse in this conversation. Create one or open one of your coupons.",
        ),
        intent: "question",
        coupons: [],
        payload: {},
        paid: false,
      };
    }
    const live = await loadLiveChecks(this.db, current.map((l) => ({ matchId: l.matchId, key: l.key })));
    const lines = current.map((l) => {
      const x = live.get(`${l.matchId}:${l.key}`);
      return { ...l, status: x?.status ?? undefined, currentOdd: x ? x.currentOdd : undefined };
    });
    const d = diagnoseCoupon(lines, this.quality?.beatsBaseline ?? null, this.now, this.lang);
    const market = d.implied_probability !== null ? ` (${this.t("marché : ", "market: ")}${this.pct(d.implied_probability)})` : "";
    const content = this.en
      ? [
        `Total odd ${this.dec(d.total_odd)}, probability estimated by the model ${this.pct(d.combined_probability)}${market}.`,
        d.fragiles.length ? `Most fragile: ${d.fragiles.map((f) => `no. ${f.position} ${f.selection}: ${f.raison}`).join("; ")}.` : "",
        d.alertes.length ? `To check: ${d.alertes.join(" ")}` : "",
      ].filter(Boolean).join(" ")
      : [
        `Cote totale ${this.dec(d.total_odd)}, probabilité estimée par le modèle ${this.pct(d.combined_probability)}${market}.`,
        d.fragiles.length ? `Les plus fragiles : ${d.fragiles.map((f) => `n° ${f.position} ${f.selection} : ${f.raison}`).join(" ; ")}.` : "",
        d.alertes.length ? `À vérifier : ${d.alertes.join(" ")}` : "",
      ].filter(Boolean).join(" ");
    return { content, intent: "analyser_coupon", coupons: [], payload: { diagnosis: d }, paid: true };
  }

  async analyzeMatches(i: Intent): Promise<Result> {
    const { cands, range } = await this.candidatesFor(i);
    const criteria = parseCriteria({
      markets: i.marches.length ? i.marches : ["1X2", "DC"],
      allowed_keys: i.issues,
      min_selection_odd: 1.2,
      max_selection_odd: 4,
      min_model_probability: 0.45,
      min_edge: 0,
      max_edge: 0.06,
      window_hours: 168,
      min_minutes_before_kickoff: 15,
      max_odds_age_hours: 24,
      require_validated_markets: !(i.marches.length || i.issues.length),
    });
    const { kept, excluded } = filterCandidates(cands, criteria, this.now, this.quality?.beatsBaseline ?? null, this.quality?.competitions ?? {});
    const ops = opportunities(kept, 8, this.lang);
    if (!ops.length) {
      return this.noResult(
        this.t(`Aucune rencontre ${range.label} ne se détache selon le modèle.`, `No match ${range.label} stands out according to the model.`),
        excluded,
      );
    }
    return {
      content: this.t(
        `${ops.length} rencontre(s) ${range.label} où le modèle estime une issue plus probable que le marché (écart positif, sans dépasser 6 points). Ce sont des estimations ; demandez-moi d'en faire un coupon si vous le souhaitez.`,
        `${ops.length} match(es) ${range.label} where the model rates an outcome as more likely than the market (positive edge, no more than 6 points). These are estimates; ask me to make a coupon from them if you wish.`,
      ),
      intent: "analyser_matchs",
      coupons: [],
      payload: { opportunities: ops },
      paid: true,
    };
  }

  // ---------------------------------------------------------------------------
  async summary(p: ProposedCoupon) {
    const fiche = {
      total_odd: p.totalOdd,
      combined_probability: p.combinedProbability,
      implied_probability: p.impliedProbability,
      selections: p.selections.map((s) => ({
        match: `${s.home} – ${s.away}`,
        competition: s.competitionName,
        kickoff: s.kickoffAt.slice(0, 16).replace("T", " "),
        selection: this.label(s.key, s.home, s.away),
        odd: s.odd,
        model_probability: s.modelProbability,
        implied_probability: s.impliedProbability,
        edge: s.edge,
        reliability: s.reliability,
      })),
      note: this.t(
        "Probabilité combinée = produit des probabilités du modèle (matchs supposés indépendants).",
        "Combined probability = product of the model probabilities (matches assumed independent).",
      ),
    };
    const { data: prompt } = await this.db.from("ai_prompts").select("system_prompt")
      .eq("key", "coupon_summary").eq("is_active", true).maybeSingle();
    if (!prompt) return { ...defaultSummary(p, this.lang), source: "calcul" };
    const { choices, pricing } = await loadAiSetup(this.db, (k) => env(k));
    const ai = await runValidated(
      fiche,
      withLanguage(prompt.system_prompt, this.lang),
      choices,
      (raw) => validateCouponSummary(raw, fiche),
      pricing,
    );
    await logAi(this.db, this.userId, "coupon_summary", ai.logs);
    return ai.status === "ok" ? { ...ai.value, source: "ia" } : { ...defaultSummary(p, this.lang), source: "calcul" };
  }

  async saveProposals(result: Result, conversationId: string, messageId: string): Promise<string[]> {
    const ids: string[] = [];
    const thresholds = (this.settings["coupons.risk_thresholds"] ?? { prudent: 0.4, equilibre: 0.18 }) as RiskThresholds;
    for (const [index, p] of result.coupons.entries()) {
      const summary = index === 0 ? await this.summary(p) : { ...defaultSummary(p, this.lang), source: "calcul" };
      const id = await insertUserCoupon(this.db, {
        userId: this.userId,
        conversationId,
        messageId,
        status: "proposal",
        title: `Coupon de l'assistant · ${p.selections.length} sélection${p.selections.length > 1 ? "s" : ""}`,
        lang: this.lang,
        criteria: result.criteria ?? {},
        proposal: p,
        risk: riskLevel(p.combinedProbability, thresholds),
        analysis: { ...summary, warnings: this.warnings, engine_quality: this.quality },
      });
      ids.push(id);
    }
    return ids;
  }
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
  const message = typeof body?.message === "string" ? body.message.trim().slice(0, 600) : "";
  const quick = typeof body?.quick === "object" && body.quick ? body.quick as Record<string, unknown> : null;
  if (!message) return json({ error: "empty_message" }, 400);

  try {
    const { data: flag } = await db.from("feature_flags").select("enabled").eq("key", "assistant_ia").maybeSingle();
    if (!flag?.enabled) return json({ error: "feature_disabled" }, 403);

    // Langue des réponses : celle de l'app, sinon celle du profil.
    let lang: Lang = asLang(body?.lang);
    if (body?.lang !== "en" && body?.lang !== "fr") {
      const { data: profile } = await db.from("profiles").select("locale").eq("id", caller.id).maybeSingle();
      lang = asLang(profile?.locale);
    }
    const en = lang === "en";
    const assistant = new Assistant(db, caller.id, new Date(), lang);
    await assistant.init();

    const dayStart = new Date();
    dayStart.setUTCHours(0, 0, 0, 0);
    const { count } = await db.from("assistant_messages").select("id", { count: "exact", head: true })
      .eq("user_id", caller.id).eq("role", "user").gte("created_at", dayStart.toISOString());
    if ((count ?? 0) >= assistant.dailyLimit) return json({ error: "daily_limit", limit: assistant.dailyLimit }, 429);

    // Conversation
    let conversationId: string | null = typeof body?.conversation_id === "string" ? body.conversation_id : null;
    if (conversationId) {
      const { data: conv } = await db.from("assistant_conversations").select("id").eq("id", conversationId)
        .eq("user_id", caller.id).maybeSingle();
      if (!conv) return json({ error: "conversation_not_found" }, 404);
    } else {
      const { data: conv, error } = await db.from("assistant_conversations")
        .insert({ user_id: caller.id, title: message.slice(0, 60) }).select("id").single();
      if (error) throw new Error(error.message);
      conversationId = conv.id;
    }
    const { data: history } = await db.from("assistant_messages").select("role, content")
      .eq("conversation_id", conversationId).order("created_at", { ascending: false }).limit(6);
    const { data: userMessage, error: umError } = await db.from("assistant_messages").insert({
      conversation_id: conversationId,
      user_id: caller.id,
      role: "user",
      content: message,
    }).select("*").single();
    if (umError) throw new Error(umError.message);

    const current = await loadUserCoupon(db, caller.id, typeof body?.coupon_id === "string" ? body.coupon_id : null, conversationId);

    // 1. Compréhension
    let intent: Intent | null = null;
    if (quick && typeof quick.intent === "string") {
      const parsed = parseIntent({ intent: quick.intent, criteres: quick.criteres ?? {}, modification: quick.modification ?? {}, reponse: "" });
      intent = parsed.ok ? parsed.value : null;
    } else {
      intent = await assistant.understand(message, (history ?? []).reverse(), current?.lines ?? null);
    }

    // 2. Exécution
    let result: Result;
    if (!intent) {
      result = {
        content: en
          ? "I could not process your request for now (AI service unavailable). Try again in a moment; no credit was charged."
          : "Je n'ai pas pu traiter votre demande pour l'instant (service d'IA indisponible). Réessayez dans un moment ; aucun crédit n'a été débité.",
        intent: "erreur",
        coupons: [],
        payload: {},
        paid: false,
      };
    } else if (intent.intent === "question") {
      result = { content: intent.reponse, intent: "question", coupons: [], payload: {}, paid: false };
    } else {
      const credits = (await db.rpc("svc_credit_summary", { p_user: caller.id })).data as { total: number; unlimited: boolean } | null;
      if (PAID_INTENTS.includes(intent.intent) && credits && !credits.unlimited && credits.total < assistant.cost) {
        result = {
          content: en
            ? `You need ${assistant.cost} credit(s) for this action and your balance is ${credits.total}. Your plan credits renew every month; credit packs are available in Subscription and credits.`
            : `Il vous faut ${assistant.cost} crédit(s) pour cette action et votre solde est de ${credits.total}. Vos crédits du forfait se renouvellent chaque mois ; des packs de crédits sont disponibles dans Abonnement et crédits.`,
          intent: "credits_insuffisants",
          coupons: [],
          payload: { credits },
          paid: false,
        };
      } else if (intent.intent === "creer_coupon" || intent.intent === "variantes") {
        result = await assistant.create(intent);
      } else if (intent.intent === "modifier_coupon") {
        result = await assistant.modify(intent, current?.lines ?? null, current?.criteria);
      } else if (intent.intent === "analyser_coupon") {
        result = await assistant.analyzeCoupon(current?.lines ?? null);
      } else {
        result = await assistant.analyzeMatches(intent);
      }
    }

    // 3. Enregistrement, puis débit après succès (une seule fois : opération = identifiant du message)
    const messageId = crypto.randomUUID();
    const warnings = [...new Set(assistant.warnings)];
    const { data: assistantMessage, error: amError } = await db.from("assistant_messages").insert({
      id: messageId,
      conversation_id: conversationId,
      user_id: caller.id,
      role: "assistant",
      content: result.content,
      intent: result.intent,
      payload: { ...result.payload, warnings },
    }).select("*").single();
    if (amError) throw new Error(amError.message);

    let couponIds: string[] = [];
    let creditState: unknown = null;
    try {
      couponIds = result.coupons.length ? await assistant.saveProposals(result, conversationId!, messageId) : [];
    } catch (e) {
      await db.from("user_coupons").delete().eq("message_id", messageId);
      await db.from("assistant_messages").delete().eq("id", messageId);
      throw e;
    }
    if (result.paid) {
      const { data, error } = await db.rpc("svc_consume_credits", {
        p_user: caller.id,
        p_operation: messageId,
        p_amount: assistant.cost,
        p_kind: `assistant:${result.intent}`,
      });
      if (error) {
        // Solde épuisé entre-temps : le résultat n'est pas conservé, rien n'est débité.
        await db.from("user_coupons").delete().eq("message_id", messageId);
        couponIds = [];
        assistantMessage.content = en
          ? "Your credit balance is no longer enough for this action: result not kept, no credit charged."
          : "Votre solde de crédits ne suffit plus pour cette action : résultat non conservé, aucun crédit débité.";
        assistantMessage.intent = "credits_insuffisants";
        assistantMessage.payload = { warnings };
      } else {
        creditState = data;
        assistantMessage.credits_charged = Number((data as { charged: number }).charged ?? 0);
        if (couponIds.length) assistantMessage.payload = { ...result.payload, warnings, coupon_ids: couponIds };
      }
      await db.from("assistant_messages").update({
        content: assistantMessage.content,
        intent: assistantMessage.intent,
        payload: assistantMessage.payload,
        credits_charged: assistantMessage.credits_charged,
      }).eq("id", messageId);
    }
    await db.from("assistant_conversations").update({ updated_at: new Date().toISOString() }).eq("id", conversationId);
    if (!creditState) creditState = (await db.rpc("svc_credit_summary", { p_user: caller.id })).data;

    return json({ conversation_id: conversationId, messages: [userMessage, assistantMessage], coupon_ids: couponIds, credits: creditState });
  } catch (e) {
    console.error("assistant", e);
    return json({ error: "internal_error", message: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});
