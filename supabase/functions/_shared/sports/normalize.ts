// Normalisation des statuts de match et des marchés de cotes. Fonctions pures, testées.
import type { MatchStatus, OddsQuote, OddsSummary } from "./types.ts";

const STATUS: Record<string, MatchStatus> = {
  TBD: "scheduled",
  NS: "scheduled",
  "1H": "live",
  HT: "live",
  "2H": "live",
  ET: "live",
  BT: "live",
  P: "live",
  LIVE: "live",
  SUSP: "interrupted",
  INT: "interrupted",
  FT: "finished",
  AET: "finished",
  PEN: "finished",
  PST: "postponed",
  CANC: "cancelled",
  ABD: "abandoned",
  AWD: "awarded",
  WO: "awarded",
};

export function normalizeStatus(short: string | null | undefined): MatchStatus {
  if (!short) return "unknown";
  return STATUS[short.toUpperCase()] ?? "unknown";
}

/** Lignes de buts suivies (les autres sont ignorées pour limiter le stockage). */
export const GOAL_LINES = [0.5, 1.5, 2.5, 3.5];

/** Lignes des buts par équipe (« Total - Home » / « Total - Away »). */
export const TEAM_GOAL_LINES = [0.5, 1.5, 2.5];

const WINNER: Record<string, string> = { home: "HOME", draw: "DRAW", away: "AWAY" };
const DOUBLE_CHANCE: Record<string, string> = { "home/draw": "1X", "home/away": "12", "draw/away": "X2" };
const YES_NO: Record<string, string> = { yes: "YES", no: "NO" };

export interface NormalizedBet {
  market: string;
  outcome: string;
  line: number | null;
}

/** Ramène un pari du fournisseur (« Match Winner » / « Home »…) à un code de marché stable. */
export function normalizeBet(betName: string, value: string): NormalizedBet | null {
  const bet = betName.trim().toLowerCase();
  const v = value.trim().toLowerCase();

  if (bet === "match winner" || bet === "1x2") {
    const outcome = WINNER[v];
    return outcome ? { market: "1X2", outcome, line: null } : null;
  }
  if (bet === "double chance") {
    const outcome = DOUBLE_CHANCE[v];
    return outcome ? { market: "DC", outcome, line: null } : null;
  }
  if (bet === "goals over/under") {
    const m = /^(over|under)\s+(\d+(?:\.\d+)?)$/.exec(v);
    if (!m) return null;
    const line = Number(m[2]);
    if (!GOAL_LINES.includes(line)) return null;
    return { market: "OU", outcome: m[1] === "over" ? "OVER" : "UNDER", line };
  }
  if (bet === "home/away" || bet === "draw no bet") {
    const outcome = v === "home" || v === "1" ? "HOME" : v === "away" || v === "2" ? "AWAY" : null;
    return outcome ? { market: "DNB", outcome, line: null } : null;
  }
  if (bet === "total - home" || bet === "total - away") {
    const m = /^(over|under)\s+(\d+(?:\.\d+)?)$/.exec(v);
    if (!m) return null;
    const line = Number(m[2]);
    if (!TEAM_GOAL_LINES.includes(line)) return null;
    return { market: bet === "total - home" ? "TTH" : "TTA", outcome: m[1] === "over" ? "OVER" : "UNDER", line };
  }
  if (bet === "both teams score" || bet === "both teams to score") {
    const outcome = YES_NO[v];
    return outcome ? { market: "BTTS", outcome, line: null } : null;
  }
  return null;
}

function median(values: number[]): number {
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const round3 = (x: number) => Math.round(x * 1000) / 1000;

/**
 * Résume les cotes de tous les bookmakers : médiane, meilleure cote et nombre de
 * bookmakers par issue. Les cotes aberrantes (≤ 1, > 1000, non numériques) sont écartées,
 * et un bookmaker n'est compté qu'une fois par issue.
 */
export function summarizeOdds(quotes: OddsQuote[]): OddsSummary[] {
  const groups = new Map<string, { market: string; outcome: string; line: number | null; byBook: Map<string, number> }>();
  for (const q of quotes) {
    if (!Number.isFinite(q.odd) || q.odd <= 1 || q.odd > 1000) continue;
    const key = `${q.market}|${q.outcome}|${q.line ?? ""}`;
    let g = groups.get(key);
    if (!g) {
      g = { market: q.market, outcome: q.outcome, line: q.line, byBook: new Map() };
      groups.set(key, g);
    }
    if (!g.byBook.has(q.bookmaker)) g.byBook.set(q.bookmaker, q.odd);
  }
  return [...groups.values()].map((g) => {
    const odds = [...g.byBook.values()];
    return {
      market: g.market,
      outcome: g.outcome,
      line: g.line,
      median: round3(median(odds)),
      best: round3(Math.max(...odds)),
      count: odds.length,
    };
  });
}

/** Comparaison en temps constant de deux secrets. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
