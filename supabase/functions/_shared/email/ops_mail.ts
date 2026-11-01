// Texte de l'e-mail d'alerte d'exploitation envoyé au super administrateur.
export interface Opened {
  id: number;
  severity: string;
  title: string;
  body: string;
}

export function alertEmail(opened: Opened[]): { subject: string; text: string } {
  const critical = opened.filter((o) => o.severity === "critical").length;
  const subject = opened.length === 1
    ? `${critical ? "Alerte" : "À surveiller"} : ${opened[0].title}`
    : `${opened.length} alertes d'exploitation${critical ? ` dont ${critical} critique(s)` : ""}`;
  const text = [
    "Coupon Pro IA : contrôle d'exploitation automatique.",
    "",
    ...opened.map((o) => `${o.severity === "critical" ? "[CRITIQUE]" : "[À surveiller]"} ${o.title}\n${o.body}\n`),
    "Détail et suivi : application → Console → Santé de l'application.",
    "Une alerte se ferme d'elle-même quand le problème disparaît.",
  ].join("\n");
  return { subject, text };
}

