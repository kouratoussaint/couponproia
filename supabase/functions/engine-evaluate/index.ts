// Edge Function : évaluation du moteur sur l'historique (réservée à ai.configure).
// Rejoue chaque match terminé de la saison avec les seuls matchs antérieurs, compare
// au résultat réel et enregistre les scores dans engine_evaluations (lisibles par tous).
import { evaluate } from "../_shared/engine/evaluate.ts";
import { ENGINE_VERSION, type PlayedMatch } from "../_shared/engine/poisson.ts";
import { callerFrom, corsHeaders, json, readSettings, serverContext } from "../_shared/http.ts";

const PAGE = 1000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const ctx = serverContext();
  if (!ctx) return json({ error: "server_misconfigured" }, 500);
  const caller = await callerFrom(req, ctx);
  if (!caller) return json({ error: "unauthorized" }, 401);
  if (!caller.permissions.includes("ai.configure")) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const { db } = ctx;
  try {
    const settings = await readSettings(db, ["sports.archive_season"]);
    const { data: competitions, error: compError } = await db.from("competitions")
      .select("id, name, current_season").eq("is_active", true);
    if (compError) throw new Error(compError.message);
    const season = Number(body?.season ?? settings["sports.archive_season"] ?? NaN);

    const groups: { name: string; matches: PlayedMatch[] }[] = [];
    for (const c of competitions ?? []) {
      const s = Number.isInteger(season) ? season : c.current_season;
      if (!s) continue;
      const matches: PlayedMatch[] = [];
      for (let from = 0;; from += PAGE) {
        const { data, error } = await db.from("matches")
          .select("kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
          .eq("competition_id", c.id).eq("season", s).in("status", ["finished", "awarded"])
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
      if (matches.length > 0) groups.push({ name: `${c.name} ${s}`, matches });
    }

    const warmupMatches = 30;
    const { evaluation, perCompetition } = evaluate(groups, { warmupMatches });
    const e = evaluation.oneXTwo;
    const { data: saved, error: saveError } = await db.from("engine_evaluations").insert({
      engine_version: ENGINE_VERSION,
      scope: {
        season: Number.isInteger(season) ? season : "en cours",
        competitions: groups.map((g) => g.name),
        warmup_matches: warmupMatches,
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
      actor_id: caller.id,
      action: "engine.evaluate",
      target_type: "engine_evaluation",
      target_id: String(saved.id),
      details: { engine_version: ENGINE_VERSION, matches: e.matches },
    });
    return json(saved);
  } catch (err) {
    console.error("engine-evaluate", err);
    return json({ error: "internal_error", message: String((err as Error).message ?? err).slice(0, 200) }, 500);
  }
});
