// Backtest « marche avant » : poisson-1.1 (en production) contre les variantes de poisson-2.0.
// Chaque match est prédit avec les seuls matchs joués avant lui. Réglages choisis sur la
// saison précédente (apprentissage), vérifiés sur la saison en cours (validation).
// Usage : deno run --allow-read scripts/engine/backtest.ts data.json > rapport.md
import { type PlayedMatch, PRIOR_SEASON_WEIGHT, runModel, weighted } from "../../supabase/functions/_shared/engine/poisson.ts";
import {
  DEFAULT_OPTIONS_2,
  fitStrengths,
  type Model2Options,
  runModel2FromStrengths,
} from "../../supabase/functions/_shared/engine/poisson2.ts";

type Row = [number, string, number, number, number, number, number, number, number];
const data = JSON.parse(await Deno.readTextFile(Deno.args[0])) as { matches: Row[]; odds: [number, string, number][] | null };
const WARMUP = 30;
const EPS = 1e-12;

interface M extends PlayedMatch {
  id: number;
  comp: number;
  compName: string;
  season: number;
  t: number;
}
const all: M[] = data.matches.map(([comp, compName, season, epoch, homeId, awayId, homeGoals, awayGoals, id]) => ({
  comp,
  compName,
  season,
  t: epoch * 1000,
  kickoffAt: new Date(epoch * 1000).toISOString(),
  homeId,
  awayId,
  homeGoals,
  awayGoals,
  id,
}));
const odds = new Map<number, Record<string, number>>();
for (const [id, outcome, odd] of data.odds ?? []) (odds.get(id) ?? odds.set(id, {}).get(id)!)[outcome] = Number(odd);

const maxSeason = Math.max(...all.map((m) => m.season));
const evalSeasons = [maxSeason - 1, maxSeason];

class Acc {
  n = 0; brier = 0; ll = 0; hit = 0; llOver = 0; llBtts = 0; brierOver = 0;
  add(p: number[], outcome: number, pOver: number, over: boolean, pBtts: number, btts: boolean) {
    this.n++;
    p.forEach((x, i) => this.brier += (x - (i === outcome ? 1 : 0)) ** 2);
    this.ll += -Math.log(Math.max(p[outcome], EPS));
    if (p.indexOf(Math.max(...p)) === outcome) this.hit++;
    this.llOver += -Math.log(Math.max(over ? pOver : 1 - pOver, EPS));
    this.brierOver += 2 * ((over ? 1 : 0) - pOver) ** 2;
    this.llBtts += -Math.log(Math.max(btts ? pBtts : 1 - pBtts, EPS));
  }
  get s() {
    const d = Math.max(1, this.n);
    return { n: this.n, brier: this.brier / d, ll: this.ll / d, acc: this.hit / d, llOver: this.llOver / d, llBtts: this.llBtts / d };
  }
}

const grid: Model2Options[] = [];
// Grille élargie après le premier passage (31/10) : le meilleur réglage était en bordure.
for (const halfLifeDays of [180, 365, 540, 730]) {
  for (const rho of [0, -0.04]) {
    for (const shrinkK of [5, 8, 12]) grid.push({ ...DEFAULT_OPTIONS_2, halfLifeDays, rho, shrinkK });
  }
}
const label = (o: Model2Options) => `demi-vie ${o.halfLifeDays} j · ρ ${o.rho} · k ${o.shrinkK}`;

// acc[model][season]
const accs = new Map<string, Map<number, Acc>>();
const accOf = (model: string, season: number) => {
  const m = accs.get(model) ?? accs.set(model, new Map()).get(model)!;
  return m.get(season) ?? m.set(season, new Acc()).get(season)!;
};
const bins = new Map<string, number[][]>();
const binOf = (model: string) => bins.get(model) ?? bins.set(model, Array.from({ length: 10 }, () => [0, 0, 0])).get(model)!;
const marketRows: { outcome: number; market: number[]; v11: number[]; v2: Record<string, number[]> }[] = [];
const perComp = new Map<string, Map<string, Acc>>();

const byComp = new Map<number, M[]>();
for (const m of all) (byComp.get(m.comp) ?? byComp.set(m.comp, []).get(m.comp)!).push(m);

for (const list of byComp.values()) {
  list.sort((a, b) => a.t - b.t);
  const cache = new Map<string, ReturnType<typeof fitStrengths>>();
  for (let i = 0; i < list.length; i++) {
    const m = list[i];
    if (!evalSeasons.includes(m.season)) continue;
    let j = i;
    while (j > 0 && list[j - 1].t === m.t) j--;
    const before = list.slice(0, j);
    const same = before.filter((x) => x.season === m.season);
    if (same.length < WARMUP) continue;
    const prior = weighted(before.filter((x) => x.season === m.season - 1), PRIOR_SEASON_WEIGHT);
    const outcome = m.homeGoals > m.awayGoals ? 0 : m.homeGoals === m.awayGoals ? 1 : 2;
    const over = m.homeGoals + m.awayGoals > 2.5;
    const btts = m.homeGoals > 0 && m.awayGoals > 0;
    const vec = (p: Record<string, number>) => [p["1X2.HOME"], p["1X2.DRAW"], p["1X2.AWAY"]];

    const p11 = runModel([...prior, ...same], m.homeId, m.awayId).probabilities;
    accOf("poisson-1.1", m.season).add(vec(p11), outcome, p11["OU.OVER.2.5"], over, p11["BTTS.YES"], btts);
    const v2: Record<string, number[]> = {};
    // Comme en production : saison en cours et saison précédente de la compétition.
    const recent = before.filter((x) => x.season >= m.season - 1);
    for (const o of grid) {
      const key = `${label(o)}|${j}`;
      const s = cache.get(key) ?? cache.set(key, fitStrengths(recent, m.t, o)).get(key)!;
      const p = runModel2FromStrengths(s, m.homeId, m.awayId, o).probabilities;
      accOf(label(o), m.season).add(vec(p), outcome, p["OU.OVER.2.5"], over, p["BTTS.YES"], btts);
      v2[label(o)] = vec(p);
      if (m.season === maxSeason) {
        const b = binOf(label(o));
        vec(p).forEach((x, k) => {
          const bin = Math.min(9, Math.floor(x * 10));
          b[bin][0]++; b[bin][1] += x; b[bin][2] += k === outcome ? 1 : 0;
        });
      }
    }
    if (m.season === maxSeason) {
      const b = binOf("poisson-1.1");
      vec(p11).forEach((x, k) => {
        const bin = Math.min(9, Math.floor(x * 10));
        b[bin][0]++; b[bin][1] += x; b[bin][2] += k === outcome ? 1 : 0;
      });
    }
    const pc = perComp.get(m.compName) ?? perComp.set(m.compName, new Map()).get(m.compName)!;
    (pc.get("poisson-1.1") ?? pc.set("poisson-1.1", new Acc()).get("poisson-1.1")!).add(vec(p11), outcome, p11["OU.OVER.2.5"], over, p11["BTTS.YES"], btts);
    for (const o of grid) {
      const l = label(o);
      (pc.get(l) ?? pc.set(l, new Acc()).get(l)!).add(v2[l], outcome, 0.5, over, 0.5, btts);
    }
    const od = odds.get(m.id);
    if (od && od.HOME && od.DRAW && od.AWAY) {
      const inv = [1 / od.HOME, 1 / od.DRAW, 1 / od.AWAY];
      const sum = inv[0] + inv[1] + inv[2];
      marketRows.push({ outcome, market: inv.map((x) => x / sum), v11: vec(p11), v2 });
    }
  }
}

const f = (x: number, d = 4) => x.toFixed(d).replace(".", ",");
const train = evalSeasons[0], valid = evalSeasons[1];
const ranked = grid.map((o) => ({ o, s: accOf(label(o), train).s })).sort((a, b) => a.s.ll - b.s.ll);
const best = label(ranked[0].o);
const out: string[] = [];
out.push(`# Backtest poisson-1.1 contre poisson-2.0 (${new Date().toISOString().slice(0, 16)} UTC)`, "");
out.push(`Matchs évalués : saison ${train} (réglage) ${accOf("poisson-1.1", train).n}, saison ${valid} (validation) ${accOf("poisson-1.1", valid).n}. Avant chaque match, au moins ${WARMUP} matchs de la même saison.`, "");
out.push("Plus bas = meilleur pour Brier et perte logarithmique (ll). Précision = issue la plus probable juste.", "");
const table = (season: number, models: string[]) => {
  out.push(`| Modèle (saison ${season}) | Matchs | Brier 1X2 | ll 1X2 | Précision | ll +2,5 buts | ll les deux marquent |`, "|---|---|---|---|---|---|---|");
  for (const name of models) {
    const s = accOf(name, season).s;
    out.push(`| ${name} | ${s.n} | ${f(s.brier)} | ${f(s.ll)} | ${f(s.acc * 100, 1)} % | ${f(s.llOver)} | ${f(s.llBtts)} |`);
  }
  out.push("");
};
out.push("## Réglage (saison précédente) : toutes les variantes", "");
table(train, ["poisson-1.1", ...ranked.map((r) => label(r.o))]);
out.push(`Meilleure variante sur la saison ${train} : **${best}**.`, "");
out.push("## Validation (saison en cours, jamais vue pendant le réglage)", "");
table(valid, ["poisson-1.1", best]);
out.push("## Calibration 1X2 (saison en cours)", "", "| Tranche | v1.1 annoncé → observé (n) | v2.0 annoncé → observé (n) |", "|---|---|---|");
const b1 = binOf("poisson-1.1"), b2 = binOf(best);
for (let i = 0; i < 10; i++) {
  if (!b1[i][0] && !b2[i][0]) continue;
  const cell = (b: number[]) => b[0] ? `${f(b[1] / b[0] * 100, 1)} % → ${f(b[2] / b[0] * 100, 1)} % (${b[0]})` : "–";
  out.push(`| ${i * 10}–${i * 10 + 10} % | ${cell(b1[i])} | ${cell(b2[i])} |`);
}
out.push("", "## Par compétition (saisons évaluées, Brier 1X2)", "", "| Compétition | Matchs | v1.1 | v2.0 |", "|---|---|---|---|");
for (const [name, pc] of [...perComp.entries()].sort()) {
  const a = pc.get("poisson-1.1")!.s, b = pc.get(best)!.s;
  out.push(`| ${name} | ${a.n} | ${f(a.brier)} | ${f(b.brier)} |`);
}
out.push("", `## Comparaison au marché (matchs avec cotes avant le coup d'envoi : ${marketRows.length})`, "");
if (marketRows.length) {
  const score = (pick: (r: typeof marketRows[0]) => number[]) => {
    let br = 0, l = 0;
    for (const r of marketRows) {
      const p = pick(r);
      p.forEach((x, k) => br += (x - (k === r.outcome ? 1 : 0)) ** 2);
      l += -Math.log(Math.max(p[r.outcome], EPS));
    }
    return `${f(br / marketRows.length)} | ${f(l / marketRows.length)}`;
  };
  const mix = (a: number[], b: number[], w: number) => a.map((x, k) => (1 - w) * x + w * b[k]);
  out.push("| Source | Brier 1X2 | ll 1X2 |", "|---|---|---|");
  out.push(`| Marché (cotes médianes, marge retirée) | ${score((r) => r.market)} |`);
  out.push(`| poisson-1.1 | ${score((r) => r.v11)} |`);
  out.push(`| ${best} | ${score((r) => r.v2[best])} |`);
  out.push(`| 30 % v1.1 + 70 % marché | ${score((r) => mix(r.v11, r.market, 0.7))} |`);
  out.push(`| 30 % v2.0 + 70 % marché | ${score((r) => mix(r.v2[best], r.market, 0.7))} |`);
  out.push("", "Échantillon encore trop petit pour conclure : les cotes de clôture ne sont conservées que depuis la mise en service.");
}
console.log(out.join("\n"));
