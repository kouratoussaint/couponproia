// Langue des textes du serveur (D5) : « fr » par défaut, « en » si demandé.

export type Lang = "fr" | "en";

/** Langue d'une valeur reçue (profil, corps de requête) : seul « en » change le français. */
export const asLang = (v: unknown): Lang => (v === "en" ? "en" : "fr");

/** Langue d'un navigateur (pages ouvertes hors de l'app) : la première langue préférée. */
export function browserLang(acceptLanguage: string | null, override?: string | null): Lang {
  if (override === "en" || override === "fr") return override;
  const first = (acceptLanguage ?? "").split(",")[0]?.trim().toLowerCase() ?? "";
  return first.startsWith("en") ? "en" : "fr";
}

/** Choix d'un texte selon la langue. */
export const pick = (lang: Lang, fr: string, en: string) => (lang === "en" ? en : fr);
