// Edge Function : évaluation du moteur sur l'historique.
// Appelée par un administrateur (JWT + ai.configure) ou par pg_cron (en-tête x-cron-secret).
// Rejoue chaque match terminé de la saison avec les seuls matchs antérieurs, compare
// au résultat réel et enregistre les scores dans engine_evaluations (lisibles par tous).
import { combineEvaluation3, evaluate, evaluate3, type Evaluation3Part, evaluate3Part, planEvaluation3 } from "../_shared/engine/evaluate.ts";
import { ENGINE_VERSION_3 } from "../_shared/engine/poisson3.ts";
import { loadModelInputs, refreshStrengths } from "../_shared/engine/strengths_store.ts";
import { type LabGroup, type LabMatch, runExperiment } from "../_shared/engine/lab3.ts";
import { ENGINE_VERSION, type PlayedMatch, PRIOR_SEASON_WEIGHT, weighted } from "../_shared/engine/poisson.ts";
import { callerFrom, corsHeaders, env, json, readSettings, serverContext } from "../_shared/http.ts";
import { safeEqual } from "../_shared/sports/normalize.ts";

const PAGE = 1000;

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
  if (caller && !caller.permissions.includes("ai.configure")) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const { db } = ctx;
  try {
    // Tâche horaire : forces du moteur poisson-3.0 (photo lue par les analyses et les coupons).
    if (body?.job === "strengths") {
      if (!fromCron && !caller) return json({ error: "unauthorized" }, 401);
      return json({ ok: true, ...await refreshStrengths(db) });
    }
    // Moteur évalué : celui de production par défaut ; « poisson-3.0 » peut être évalué avant la
    // bascule (LOT 28) pour que la qualité par compétition existe dès l'activation.
    const production: string = ENGINE_VERSION;
    const engine = body?.engine === ENGINE_VERSION_3 || production === ENGINE_VERSION_3 ? ENGINE_VERSION_3 : production;

    const settings = await readSettings(db, ["sports.archive_season"]);
    const { data: competitions, error: compError } = await db.from("competitions")
      .select("id, name, display_name, current_season").eq("is_active", true);
    if (compError) throw new Error(compError.message);
    const season = Number(body?.season ?? settings["sports.archive_season"] ?? NaN);

    const priorWeight = Number.isFinite(Number(body?.prior_weight)) ? Number(body.prior_weight) : PRIOR_SEASON_WEIGHT;
    const dryRun = body?.dry_run === true;

    // poisson-3.0 : évaluation officielle découpée en lots enchaînés (limite de calcul du serveur,
    // dépassée le 16/11 avec 28 compétitions). Un administrateur attend le résultat ; la tâche
    // du lundi lance la chaîne et rend la main.
    if (engine === ENGINE_VERSION_3 && body?.experiment !== "moteur-3" && !dryRun) {
      if (!cronSecret) return json({ error: "server_misconfigured" }, 500);
      if (body?.run) {
        if (!fromCron) return json({ error: "forbidden" }, 403);
        runInBackground(evaluationPart(db, competitions ?? [], body as PartBody, cronSecret));
        return json({ accepted: true, run: body.run, part: body.part }, 202);
      }
      return json(
        await startEvaluation3(db, competitions ?? [], season, cronSecret, {
          actorId: caller?.id ?? null,
          source: fromCron ? "cron" : "admin",
          wait: !fromCron,
        }),
      );
    }

    const load = async (competitionId: number, season: number) => {
      const matches: PlayedMatch[] = [];
      for (let from = 0;; from += PAGE) {
        const { data, error } = await db.from("matches")
          .select("kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
          .eq("competition_id", competitionId).eq("season", season).in("status", ["finished", "awarded"])
          .not("home_goals", "is", null).not("away_goals", "is", null)
          .order("kickoff_at").order("id").range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        for (const r of data ?? []) {
          matches.push({
            kickoffAt: r.kickoff_at,
            homeId: r.home_team_id,
            awayId: r.away_team_id,
            homeGoals: r.home_goals,
            awayGoals: r.away_goals,
          });
        }
        if (!data || data.length < PAGE) break;
      }
      return matches;
    };

    // Par défaut (tâche hebdomadaire) : saison précédente complète + saison en cours.
    // Compétitions repérées par leur identifiant (« 5:2025 ») : deux « Ligue 1 » restent séparées.
    const groups: { name: string; competitionId: number; season: number; matches: PlayedMatch[]; prior: PlayedMatch[] }[] = [];
    const labels: Record<string, string> = {};
    for (const c of competitions ?? []) {
      const seasons = Number.isInteger(season) ? [season] : c.current_season ? [c.current_season - 1, c.current_season] : [];
      for (const s of seasons) {
        const matches = await load(c.id, s);
        if (matches.length === 0) continue;
        const prior = priorWeight > 0 ? weighted(await load(c.id, s - 1), priorWeight) : [];
        groups.push({ name: `${c.id}:${s}`, competitionId: c.id, season: s, matches, prior });
        labels[`${c.id}:${s}`] = `${c.display_name ?? c.name} ${s}`;
      }
    }

    const warmupMatches = 30;

    // Laboratoire « Moteur 3.0 » : comparaison de variantes, rien n'est enregistré.
    if (body?.experiment === "moteur-3") {
      // Options : `only` (identifiants de compétitions), `refit` ("week" par défaut, ou "day"),
      // `with_b` (variante B, oui par défaut), `variant_c` (niveau des championnats).
      const only = Array.isArray(body?.only) ? new Set(body.only.map(Number)) : null;
      const refit = body?.refit === "day" ? "day" : "week";
      const withB = body?.with_b !== false;
      const variantC = body?.variant_c === true;
      const chosen = only ? groups.filter((g) => only.has(g.competitionId)) : groups;
      return json({ experiment: "moteur-3", refit, labels, ...await moteur3(db, chosen, { refit, withB, variantC }) });
    }

    const { evaluation, perCompetition } = engine === ENGINE_VERSION_3
      ? await (async () => {
        const { matches, leagues } = await loadModelInputs(db, new Date());
        return evaluate3(groups, matches, leagues, { warmupMatches });
      })()
      : evaluate(groups, { warmupMatches });
    if (dryRun) return json({ dry_run: true, prior_weight: priorWeight, evaluation, perCompetition, labels });
    const saved = await saveEvaluation(db, {
      engine,
      evaluation,
      perCompetition,
      labels,
      names: groups.map((g) => g.name),
      season,
      warmupMatches,
      priorWeight,
      actorId: caller?.id ?? null,
      source: fromCron ? "cron" : "admin",
    });
    return json(saved);
  } catch (err) {
    console.error("engine-evaluate", err);
    return json({ error: "internal_error", message: String((err as Error).message ?? err).slice(0, 200) }, 500);
  }
});

/**
 * Expérience « Moteur 3.0 » (laboratoire, lecture seule) : mêmes compétitions-saisons que
 * l'évaluation officielle ; tous les matchs terminés connus servent aux forces « reliées » ;
 * dernier relevé de cotes 1X2 avant le coup d'envoi pour la comparaison avec le marché.
 */
async function moteur3(
  // deno-lint-ignore no-explicit-any
  db: any,
  groups: { name: string; competitionId: number; season: number; prior: PlayedMatch[] }[],
  opts: { refit: "week" | "day"; withB: boolean; variantC: boolean },
) {
  const all: LabMatch[] = [];
  for (let from = 0;; from += PAGE) {
    const { data, error } = await db.from("matches")
      .select("id, competition_id, season, kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
      .in("status", ["finished", "awarded"]).not("home_goals", "is", null).not("away_goals", "is", null)
      .order("id").range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    for (const r of data ?? []) {
      all.push({
        id: r.id,
        competitionId: r.competition_id,
        season: r.season,
        kickoffAt: r.kickoff_at,
        homeId: r.home_team_id,
        awayId: r.away_team_id,
        homeGoals: r.home_goals,
        awayGoals: r.away_goals,
      });
    }
    if (!data || data.length < PAGE) break;
  }
  const labGroups: LabGroup[] = groups.map((g) => ({
    key: g.name,
    competitionId: g.competitionId,
    season: g.season,
    matches: all.filter((m) => m.competitionId === g.competitionId && m.season === g.season),
    prior: g.prior,
  }));

  // Cotes : dernier relevé 1X2 avant le coup d'envoi, pour les matchs terminés.
  const kickoff = new Map(all.map((m) => [m.id, m.kickoffAt]));
  const latest = new Map<number, { at: string; home?: number; draw?: number; away?: number }>();
  for (let from = 0;; from += PAGE) {
    const { data, error } = await db.from("odds_snapshots")
      .select("match_id, outcome_code, odd_median, captured_at")
      .eq("market_code", "1X2").order("id").range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    for (const r of data ?? []) {
      const k = kickoff.get(r.match_id);
      if (!k || r.captured_at >= k) continue;
      const cur = latest.get(r.match_id);
      const at = String(r.captured_at).slice(0, 16);
      const row = !cur || at > cur.at ? { at } : cur;
      if (cur && at < cur.at) continue;
      const key = String(r.outcome_code).toLowerCase() as "home" | "draw" | "away";
      row[key] = Number(r.odd_median);
      latest.set(r.match_id, row);
    }
    if (!data || data.length < PAGE) break;
  }
  const odds = new Map<number, { home: number; draw: number; away: number }>();
  for (const [id, o] of latest) {
    if (o.home && o.draw && o.away) odds.set(id, { home: o.home, draw: o.draw, away: o.away });
  }
  const t0 = performance.now();
  let leagues: Set<number> | null = null;
  if (opts.variantC) {
    const { data, error } = await db.from("competitions").select("id, type");
    if (error) throw new Error(error.message);
    leagues = new Set((data ?? []).filter((c: { type: string }) => c.type === "league").map((c: { id: number }) => c.id));
  }
  const result = runExperiment(labGroups, all, odds, 30, undefined, { refit: opts.refit, withB: opts.withB, leagues });
  return { all_matches: all.length, matches_with_odds: odds.size, compute_ms: Math.round(performance.now() - t0), ...result };
}

// ---------------------------------------------------------------- enregistrement

interface SaveInput {
  engine: string;
  evaluation: ReturnType<typeof evaluate>["evaluation"];
  perCompetition: ReturnType<typeof evaluate>["perCompetition"];
  labels: Record<string, string>;
  names: string[];
  season: number;
  warmupMatches: number;
  priorWeight: number;
  actorId: string | null;
  source: string;
  run?: string;
  parts?: number;
}

// deno-lint-ignore no-explicit-any
async function saveEvaluation(db: any, x: SaveInput) {
  const e = x.evaluation.oneXTwo;
  const { data: saved, error: saveError } = await db.from("engine_evaluations").insert({
    engine_version: x.engine,
    scope: {
      season: Number.isInteger(x.season) ? x.season : "précédente et en cours",
      competitions: x.names.map((n) => x.labels[n] ?? n),
      warmup_matches: x.warmupMatches,
      prior_season_weight: x.priorWeight,
      ...(x.run ? { run: x.run, parts: x.parts } : {}),
      method: x.engine === ENGINE_VERSION_3
        ? "Chaque match est prédit avec les seuls matchs antérieurs, toutes compétitions (forces de la veille)"
        : "Chaque match est prédit avec les seuls matchs antérieurs de sa compétition",
    },
    matches_evaluated: e.matches,
    brier_model: e.brierModel,
    brier_baseline: e.brierBaseline,
    logloss_model: e.loglossModel,
    logloss_baseline: e.loglossBaseline,
    accuracy_model: e.accuracyModel,
    calibration: x.evaluation.calibration,
    details: {
      accuracy_baseline: e.accuracyBaseline,
      over_2_5: x.evaluation.over25,
      btts: x.evaluation.btts,
      dnb: x.evaluation.dnb,
      team_totals: x.evaluation.teamTotals,
      // Affichage (nom affiché + saison) et qualité par identifiant (« 5:2025 »), lue par le moteur.
      per_competition: Object.fromEntries(Object.entries(x.perCompetition).map(([k, v]) => [x.labels[k] ?? k, v])),
      per_competition_ids: x.perCompetition,
    },
  }).select().single();
  if (saveError) throw new Error(saveError.message);

  await db.from("audit_logs").insert({
    actor_id: x.actorId,
    action: "engine.evaluate",
    target_type: "engine_evaluation",
    target_id: String(saved.id),
    details: { engine_version: x.engine, matches: e.matches, source: x.source, ...(x.run ? { run: x.run, parts: x.parts } : {}) },
  });
  return saved;
}

// ---------------------------------------------------------------- poisson-3.0 par lots

/** Jours de calcul distincts par lot : environ 0,3 s de calcul par lot avec 13 000 matchs. */
const DAYS_PER_PART = 120;
const WARMUP = 30;

type Competition = { id: number; name: string; display_name: string | null; current_season: number | null };
type PartBody = { run: string; part: number; plan: string[][]; at: string; season: number | null; actor: string | null; source: string };

function runInBackground(task: Promise<unknown>): void {
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) runtime.waitUntil(task);
}

/** Compétitions-saisons évaluées (saison demandée, ou précédente + en cours), depuis les matchs chargés. */
function groups3(competitions: Competition[], matches: (PlayedMatch & { competitionId: number; season: number })[], season: number | null) {
  const byKey = new Map<string, PlayedMatch[]>();
  for (const m of matches) {
    const k = `${m.competitionId}:${m.season}`;
    (byKey.get(k) ?? byKey.set(k, []).get(k)!).push(m);
  }
  const groups: { name: string; competitionId: number; matches: PlayedMatch[] }[] = [];
  const labels: Record<string, string> = {};
  for (const c of competitions) {
    const seasons = Number.isInteger(season) ? [season!] : c.current_season ? [c.current_season - 1, c.current_season] : [];
    for (const s of seasons) {
      const ms = byKey.get(`${c.id}:${s}`) ?? [];
      if (ms.length === 0) continue;
      groups.push({ name: `${c.id}:${s}`, competitionId: c.id, matches: ms });
      labels[`${c.id}:${s}`] = `${c.display_name ?? c.name} ${s}`;
    }
  }
  return { groups, labels };
}

async function callPart(secret: string, body: PartBody) {
  const res = await fetch(`${env("SUPABASE_URL")}/functions/v1/engine-evaluate`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-cron-secret": secret },
    body: JSON.stringify({ engine: ENGINE_VERSION_3, ...body }),
  });
  if (res.status !== 202) throw new Error(`lot ${body.part} non lancé (${res.status})`);
}

async function startEvaluation3(
  // deno-lint-ignore no-explicit-any
  db: any,
  competitions: Competition[],
  season: number,
  secret: string,
  opts: { actorId: string | null; source: string; wait: boolean },
) {
  const at = new Date().toISOString();
  const { matches } = await loadModelInputs(db, new Date(at));
  const seasonOrNull = Number.isInteger(season) ? season : null;
  const { groups } = groups3(competitions, matches, seasonOrNull);
  const plan = planEvaluation3(groups, DAYS_PER_PART, WARMUP);
  if (plan.length === 0) return { error: "no_data" };
  const run = crypto.randomUUID();
  await callPart(secret, { run, part: 0, plan, at, season: seasonOrNull, actor: opts.actorId, source: opts.source });
  if (!opts.wait) return { accepted: true, run, parts: plan.length };
  // Administrateur (console) : attendre l'évaluation complète, comme avant le découpage.
  for (let i = 0; i < 45; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    const { data: saved } = await db.from("engine_evaluations").select("*").eq("scope->>run", run).maybeSingle();
    if (saved) return saved;
    const { data: failed } = await db.from("engine_evaluation_parts").select("part, error").eq("run_id", run)
      .not("error", "is", null).limit(1).maybeSingle();
    if (failed) throw new Error(`évaluation interrompue au lot ${failed.part + 1} : ${failed.error}`);
  }
  throw new Error("évaluation encore en cours : résultat visible dans quelques minutes");
}

// deno-lint-ignore no-explicit-any
async function evaluationPart(db: any, competitions: Competition[], body: PartBody, secret: string) {
  const parts = body.plan.length;
  try {
    const { matches, leagues } = await loadModelInputs(db, new Date(body.at));
    const names = new Set(body.plan[body.part] ?? []);
    const { groups, labels } = groups3(competitions, matches, body.season);
    const payload = evaluate3Part(groups.filter((g) => names.has(g.name)), matches, leagues, { warmupMatches: WARMUP });
    const { error } = await db.from("engine_evaluation_parts").upsert({
      run_id: body.run,
      part: body.part,
      parts,
      engine_version: ENGINE_VERSION_3,
      payload,
    });
    if (error) throw new Error(error.message);
    if (body.part + 1 < parts) {
      await callPart(secret, { ...body, part: body.part + 1 });
      return;
    }
    // Dernier lot : additionner, enregistrer l'évaluation, effacer les lots.
    const { data: rows, error: readError } = await db.from("engine_evaluation_parts").select("part, payload")
      .eq("run_id", body.run).order("part");
    if (readError) throw new Error(readError.message);
    if ((rows ?? []).length !== parts) throw new Error(`lots manquants (${(rows ?? []).length}/${parts})`);
    const { evaluation, perCompetition } = combineEvaluation3((rows ?? []).map((r: { payload: Evaluation3Part }) => r.payload));
    await saveEvaluation(db, {
      engine: ENGINE_VERSION_3,
      evaluation,
      perCompetition,
      labels,
      names: body.plan.flat(),
      season: body.season ?? NaN,
      warmupMatches: WARMUP,
      priorWeight: PRIOR_SEASON_WEIGHT,
      actorId: body.actor,
      source: body.source,
      run: body.run,
      parts,
    });
    await db.from("engine_evaluation_parts").delete().eq("run_id", body.run);
  } catch (err) {
    console.error("engine-evaluate lot", body.part, err);
    await db.from("engine_evaluation_parts").upsert({
      run_id: body.run,
      part: body.part,
      parts,
      engine_version: ENGINE_VERSION_3,
      error: String((err as Error).message ?? err).slice(0, 300),
    });
  }
}
