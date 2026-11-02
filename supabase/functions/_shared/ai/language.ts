// Langue des textes rédigés par l'IA (D5) : consigne ajoutée au prompt actif quand l'utilisateur
// a choisi l'anglais. Le prompt de la console reste écrit en français ; les clés JSON ne changent pas.
import type { Lang } from "../lang.ts";

export const ENGLISH_INSTRUCTION = [
  "",
  "LANGUE DE LA RÉPONSE : ANGLAIS.",
  "- Rédige toutes les valeurs texte en anglais clair et simple ; garde exactement les mêmes clés JSON.",
  "- Dans la fiche, la forme s'écrit V (victoire = win), N (nul = draw), D (défaite = loss) : écris win, draw, loss.",
  "- Ce sont des estimations : n'écris jamais guaranteed, sure bet, certainty, risk-free, winnings, can't lose ni 100 %.",
  "- Les nombres s'écrivent avec un point décimal (1.85) et viennent tous de la fiche.",
].join("\n");

/** Prompt système dans la langue demandée. */
export const withLanguage = (systemPrompt: string, lang: Lang) =>
  lang === "en" ? `${systemPrompt}\n${ENGLISH_INSTRUCTION}` : systemPrompt;
