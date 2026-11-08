// Edge Function : évaluation du moteur sur l'historique.
// Appelée par un administrateur (JWT + ai.configure) ou par pg_cron (en-tête x-cron-secret).
// Rejoue chaque match terminé de la saison avec les seuls matchs antérieurs, compare
// au résultat réel et enregistre les scores dans engine_evaluations (lisibles par tous).
import { evaluate, evaluate3 } from "../_shared/engine/evaluate.ts";
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
    const e = evaluation.oneXTwo;
    if (dryRun) return json({ dry_run: true, prior_weight: priorWeight, evaluation, perCompetition, labels });
    const { data: saved, error: saveError } = await db.from("engine_evaluations").insert({
      engine_version: engine,
      scope: {
        season: Number.isInteger(season) ? season : "précédente et en cours",
        competitions: groups.map((g) => labels[g.name] ?? g.name),
        warmup_matches: warmupMatches,
        prior_season_weight: priorWeight,
        method: engine === ENGINE_VERSION_3
          ? "Chaque match est prédit avec les seuls matchs antérieurs, toutes compétitions (forces de la veille)"
          : "Chaque match est prédit avec les seuls matchs antérieurs de sa compétition",
      },
      matches_evaluated: e.matches,
      brier_model: e.brierModel,
      brier_baseline: e.brierBaseline,
      logloss_model: e.loglossModel,
      logloss_baseline: e.loglossBaseline,
      accuracy_model: e.accuracyModel,
      calibration: evaluation.calibration,
      details: {
        accuracy_baseline: e.accuracyBaseline,
        over_2_5: evaluation.over25,
        btts: evaluation.btts,
        dnb: evaluation.dnb,
        team_totals: evaluation.teamTotals,
        // Affichage (nom affiché + saison) et qualité par identifiant (« 5:2025 »), lue par le moteur.
        per_competition: Object.fromEntries(Object.entries(perCompetition).map(([k, v]) => [labels[k] ?? k, v])),
        per_competition_ids: perCompetition,
      },
    }).select().single();
    if (saveError) throw new Error(saveError.message);

    await db.from("audit_logs").insert({
      actor_id: caller?.id ?? null,
      action: "engine.evaluate",
      target_type: "engine_evaluation",
      target_id: String(saved.id),
      details: { engine_version: engine, matches: e.matches, source: fromCron ? "cron" : "admin" },
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
