// Forces du moteur poisson-3.0 : calcul sur tous les matchs terminés, photo horaire
// (table engine_strengths, réservée au serveur) et lecture par les analyses et les coupons.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { ENGINE_VERSION_3, fromSnapshot, type Match3, type Strengths3, strengthsAt, toSnapshot } from "./poisson3.ts";

const PAGE = 1000;
const PLAYED = ["finished", "awarded"];
/** Au-delà, la photo est jugée trop ancienne : calcul direct. */
export const SNAPSHOT_MAX_AGE_MS = 3 * 3600_000;

/** Tous les matchs terminés avant `before` (toutes compétitions) et les championnats nationaux. */
export async function loadModelInputs(db: SupabaseClient, before: Date) {
  const matches: Match3[] = [];
  for (let from = 0;; from += PAGE) {
    const { data, error } = await db.from("matches")
      .select("competition_id, kickoff_at, home_team_id, away_team_id, home_goals, away_goals")
      .in("status", PLAYED).lt("kickoff_at", before.toISOString())
      .not("home_goals", "is", null).not("away_goals", "is", null)
      .order("kickoff_at").order("id").range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    for (const r of data ?? []) {
      matches.push({
        competitionId: r.competition_id,
        kickoffAt: r.kickoff_at,
        homeId: r.home_team_id,
        awayId: r.away_team_id,
        homeGoals: r.home_goals,
        awayGoals: r.away_goals,
      });
    }
    if (!data || data.length < PAGE) break;
  }
  const { data: comps, error } = await db.from("competitions").select("id, type");
  if (error) throw new Error(error.message);
  const leagues = new Set((comps ?? []).filter((c) => c.type === "league").map((c) => Number(c.id)));
  return { matches, leagues };
}

/** Calcule les forces à une date (matchs terminés avant cette date). */
export async function computeStrengths(db: SupabaseClient, at: Date): Promise<{ strengths: Strengths3; matches: number }> {
  const { matches, leagues } = await loadModelInputs(db, at);
  return { strengths: strengthsAt(matches, at.getTime(), leagues), matches: matches.length };
}

/** Tâche horaire : calcule et enregistre la photo, garde deux jours d'historique. */
export async function refreshStrengths(db: SupabaseClient, now = new Date()) {
  const { strengths, matches } = await computeStrengths(db, now);
  const { error } = await db.from("engine_strengths").insert({
    engine_version: ENGINE_VERSION_3,
    computed_at: now.toISOString(),
    matches,
    data: toSnapshot(strengths),
  });
  if (error) throw new Error(error.message);
  await db.from("engine_strengths").delete().lt("computed_at", new Date(now.getTime() - 2 * 86400_000).toISOString());
  return { matches, teams: strengths.attack.size, leagues: Object.fromEntries(strengths.leagueLevel) };
}

/**
 * Forces pour prédire un match qui commence à `kickoff` : la photo récente pour un match à venir ;
 * sinon (match passé, ou photo absente / trop ancienne) calcul direct avec les seuls matchs
 * terminés avant le coup d'envoi.
 */
export async function strengthsFor(db: SupabaseClient, kickoff: Date, now = new Date()): Promise<Strengths3> {
  if (kickoff.getTime() > now.getTime()) {
    const { data } = await db.from("engine_strengths").select("computed_at, data")
      .eq("engine_version", ENGINE_VERSION_3).order("computed_at", { ascending: false }).limit(1).maybeSingle();
    if (data && now.getTime() - Date.parse(data.computed_at) < SNAPSHOT_MAX_AGE_MS) return fromSnapshot(data.data);
    return (await computeStrengths(db, now)).strengths;
  }
  return (await computeStrengths(db, kickoff)).strengths;
}
