// Edge Function : évaluation du moteur sur l'historique.
// Appelée par un administrateur (JWT + ai.configure) ou par pg_cron (en-tête x-cron-secret).
// Rejoue chaque match terminé de la saison avec les seuls matchs antérieurs, compare
// au résultat réel et enregistre les scores dans engine_evaluations (lisibles par tous).
import { evaluate } from "../_shared/engine/evaluate.ts";
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
    const settings = await readSettings(db, ["sports.archive_season"]);
    const { data: competitions, error: compError } = await db.from("competitions")
      .select("id, name, current_season").eq("is_active", true);
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

    const groups: { name: string; matches: PlayedMatch[]; prior: PlayedMatch[] }[] = [];
    for (const c of competitions ?? []) {
      const s = Number.isInteger(season) ? season : c.current_season;
      if (!s) continue;
      const matches = await load(c.id, s);
      if (matches.length === 0) continue;
      const prior = priorWeight > 0 ? weighted(await load(c.id, s - 1), priorWeight) : [];
      groups.push({ name: `${c.name} ${s}`, matches, prior });
    }

    const warmupMatches = 30;
    const { evaluation, perCompetition } = evaluate(groups, { warmupMatches });
    const e = evaluation.oneXTwo;
    if (dryRun) return json({ dry_run: true, prior_weight: priorWeight, evaluation, perCompetition });
    const { data: saved, error: saveError } = await db.from("engine_evaluations").insert({
      engine_version: ENGINE_VERSION,
      scope: {
        season: Number.isInteger(season) ? season : "en cours",
        competitions: groups.map((g) => g.name),
        warmup_matches: warmupMatches,
        prior_season_weight: priorWeight,
        method: "Chaque match est prédit avec les seuls matchs antérieurs de sa compétition",
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
        per_competition: perCompetition,
      },
    }).select().single();
    if (saveError) throw new Error(saveError.message);

    await db.from("audit_logs").insert({
      actor_id: caller?.id ?? null,
      action: "engine.evaluate",
      target_type: "engine_evaluation",
      target_id: String(saved.id),
      details: { engine_version: ENGINE_VERSION, matches: e.matches, source: fromCron ? "cron" : "admin" },
    });
    return json(saved);
  } catch (err) {
    console.error("engine-evaluate", err);
    return json({ error: "internal_error", message: String((err as Error).message ?? err).slice(0, 200) }, 500);
  }
});
