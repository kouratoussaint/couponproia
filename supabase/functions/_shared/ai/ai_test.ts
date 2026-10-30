// Tests unitaires de la couche IA : `deno test supabase/functions/_shared`
import { assert, assertEquals } from "jsr:@std/assert@1";
import { analyzeWithAi, estimateCost } from "./analyst.ts";
import { type AiProvider, GeminiProvider } from "./providers.ts";
import { FORBIDDEN, unknownNumbers, validateAnalysis } from "./validate.ts";

const fiche = {
  reliability: "bonne",
  sample: { home_team_home_matches: 9 },
  model: {
    expected_goals_home: 1.62,
    probabilities: { "1X2.HOME": 0.532, "1X2.DRAW": 0.241, "OU.OVER.2.5": 0.551 },
  },
  teams: { home: { standing: { rank: 4, points: 45 } } },
  head_to_head: [{ date: "2024-02-17", score: "2-1" }],
  market: { lines: [{ key: "1X2.HOME", odd_median: 1.95, implied_probability: 0.49, edge: 0.042 }] },
};

const good = {
  resume: "Alpha part favori à domicile avec 53 % selon le modèle.",
  forme: "Alpha est 4e avec 45 points ; 1,62 but attendu.",
  facteurs_domicile: ["Bon bilan à domicile (9 matchs)."],
  facteurs_exterieur: ["Défense fragile à l'extérieur."],
  tendances: ["Plus de 2,5 buts estimé à 55 %."],
  marches_envisageables: [{ cle: "1X2.HOME", probabilite_modele: 0.53, justification: "Cote médiane 1,95 pour 53 %." }],
  risques: ["Le nul reste possible (24 %)."],
  informations_manquantes: ["Compositions inconnues."],
  conclusion: "Avantage Alpha, à confirmer.",
  recommandation_possible: true,
};

Deno.test("validation : réponse conforme acceptée, probabilité remplacée par celle du moteur", () => {
  const r = validateAnalysis(good, fiche);
  assert(r.ok, r.ok ? "" : r.errors.join(" / "));
  assertEquals(r.analysis.marches_envisageables[0].probabilite_modele, 0.532);
  assertEquals(r.analysis.marches_envisageables[0].cote_mediane, 1.95);
  assertEquals(r.analysis.marches_envisageables[0].ecart, 0.042);
});

Deno.test("validation : nombre inventé refusé", () => {
  const r = validateAnalysis({ ...good, forme: "Alpha a gagné 78 % de ses matchs." }, fiche);
  assert(!r.ok && r.errors.some((e) => e.includes("78")));
});

Deno.test("validation : marché inconnu ou probabilité modifiée refusés", () => {
  const r1 = validateAnalysis({ ...good, marches_envisageables: [{ cle: "BTTS.YES", probabilite_modele: 0.6, justification: "x" }] }, fiche);
  assert(!r1.ok);
  const r2 = validateAnalysis({ ...good, marches_envisageables: [{ cle: "1X2.HOME", probabilite_modele: 0.7, justification: "x" }] }, fiche);
  assert(!r2.ok);
});

Deno.test("validation : mots de certitude interdits, sans faux positifs", () => {
  for (const s of ["victoire sûre", "pari garanti", "succès assuré", "à 100 %", "gain facile", "aucune certitude"]) {
    assert(FORBIDDEN.test(s), s);
  }
  for (const s of ["sur 10 matchs", "assurer la défense", "certaines équipes", "surtout", "regain de forme"]) {
    assert(!FORBIDDEN.test(s), s);
  }
  const r = validateAnalysis({ ...good, conclusion: "Une victoire quasi sûre." }, fiche);
  assert(!r.ok);
});

Deno.test("validation : pas de recommandation si fiabilité faible", () => {
  const r = validateAnalysis(good, { ...fiche, reliability: "faible" });
  assert(r.ok);
  assertEquals(r.analysis.recommandation_possible, false);
});

Deno.test("nombres : années, petits comptes et dates de la fiche tolérés", () => {
  assertEquals(unknownNumbers("Saison 2024, 3 derniers matchs, le 17/02 score 2-1", [17, 2, 1, 2024]), []);
  assertEquals(unknownNumbers("53 % et 1,6 but", [53.2, 1.62]), []);
  assertEquals(unknownNumbers("environ 61 %", [53.2]), ["61 %"]);
});

function fakeProvider(name: string, replies: (string | Error)[]): AiProvider & { calls: string[] } {
  const calls: string[] = [];
  return {
    name,
    calls,
    call(_s: string, user: string, model: string) {
      calls.push(user);
      const r = replies.shift();
      if (r instanceof Error || r === undefined) return Promise.reject(r ?? new Error("plus de réponse"));
      return Promise.resolve({ text: r, model, inputTokens: 1000, outputTokens: 200 });
    },
  };
}

Deno.test("orchestration : correction après refus, puis succès", async () => {
  const p = fakeProvider("gemini", [JSON.stringify({ ...good, resume: "Victoire garantie." }), "```json\n" + JSON.stringify(good) + "\n```"]);
  const r = await analyzeWithAi(fiche, "système", [{ provider: p, model: "m1" }], { m1: [0.3, 2.5] });
  assertEquals(r.status, "ok");
  assertEquals(r.logs[0].attempts, 2);
  assertEquals(r.logs[0].inputTokens, 2000);
  assertEquals(r.logs[0].costUsd, estimateCost({ m1: [0.3, 2.5] }, "m1", 2000, 400));
  assert(p.calls[1].includes("garanti"), "les erreurs sont renvoyées à l'IA");
});

Deno.test("orchestration : fournisseur en panne → secours ; tout échoue → fiche seule", async () => {
  const down = fakeProvider("gemini", [new Error("503")]);
  const backup = fakeProvider("groq", [JSON.stringify(good)]);
  const ok = await analyzeWithAi(fiche, "s", [{ provider: down, model: "a" }, { provider: backup, model: "b" }]);
  assertEquals(ok.status, "ok");
  assertEquals(ok.logs.map((l) => l.status), ["error", "success"]);

  const bad = fakeProvider("gemini", ["pas du json", "toujours pas"]);
  const ko = await analyzeWithAi(fiche, "s", [{ provider: bad, model: "a" }]);
  assertEquals(ko.status, "stats_only");
  if (ko.status === "stats_only") assertEquals(ko.reason, "validation_failed");
  const none = await analyzeWithAi(fiche, "s", []);
  assertEquals(none.status, "stats_only");
});

Deno.test("Gemini : modèle introuvable → choix du flash-lite disponible le plus récent", async () => {
  const urls: string[] = [];
  const fetchFn = ((url: string) => {
    urls.push(url);
    if (url.includes("gemini-9-lite:generateContent")) return Promise.resolve(new Response("not found", { status: 404 }));
    if (url.includes("/models?")) {
      return Promise.resolve(Response.json({
        models: [
          { name: "models/gemini-2.5-flash-lite", supportedGenerationMethods: ["generateContent"] },
          { name: "models/gemini-3.5-flash-lite", supportedGenerationMethods: ["generateContent"] },
          { name: "models/gemini-3.5-flash", supportedGenerationMethods: ["generateContent"] },
          { name: "models/gemini-3.6-flash-lite-preview", supportedGenerationMethods: ["generateContent"] },
        ],
      }));
    }
    return Promise.resolve(Response.json({
      candidates: [{ content: { parts: [{ text: "{}" }] } }],
      usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 },
    }));
  }) as typeof fetch;
  const g = new GeminiProvider("k", fetchFn);
  const r = await g.call("s", "u", "gemini-9-lite");
  assertEquals(r.model, "gemini-3.5-flash-lite");
  assertEquals(r.inputTokens, 10);
  assert(urls.at(-1)!.includes("gemini-3.5-flash-lite:generateContent"));
});
