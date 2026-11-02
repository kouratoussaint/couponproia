// Rapport hebdomadaire par e-mail (C5) : texte simple, chiffres réels des 7 derniers jours,
// pertes comprises, sans promesse de résultat. Fonction pure, testée.
export interface Counts {
  won: number;
  lost: number;
  void: number;
}
export interface JournalWeek {
  bets: number;
  won: number;
  lost: number;
  staked: number;
  returned: number;
}
export interface Recipient {
  user_id: string;
  email: string;
  name: string;
  mine: Counts;
  journal: JournalWeek;
}
export interface PlatformWeek extends Counts {
  avg_won_odd: number | null;
}

const two = (n: number) => String(n).padStart(2, "0");
const day = (d: Date) => `${two(d.getUTCDate())}/${two(d.getUTCMonth() + 1)}`;
/** 12 500 (espace fine insécable remplacée par une espace simple pour les clients mail). */
export const money = (n: number) => Math.round(n).toLocaleString("fr-FR").replace(/\s/g, " ");
const plural = (n: number, one: string, many: string) => `${n} ${n > 1 ? many : one}`;

function decided(c: Counts, wonWord = ["gagné", "gagnés"], lostWord = ["perdu", "perdus"]): string {
  const parts = [plural(c.won, wonWord[0], wonWord[1]), plural(c.lost, lostWord[0], lostWord[1])];
  if (c.void) parts.push(plural(c.void, "annulé", "annulés"));
  return parts.join(", ");
}

export function weeklyEmail(
  r: Recipient,
  platform: PlatformWeek,
  since: Date,
  until: Date,
  currency = "FCFA",
): { subject: string; text: string } {
  const period = `du ${day(since)} au ${day(until)}`;
  const mineTotal = r.mine.won + r.mine.lost + r.mine.void;
  const pDecided = platform.won + platform.lost;
  const pTotal = pDecided + platform.void;
  const net = r.journal.returned - r.journal.staked;
  const lines = [
    `Bonjour${r.name ? ` ${r.name}` : ""},`,
    "",
    `Voici votre semaine sur Coupon Pro IA (${period}), pertes comprises.`,
    "",
    "MES COUPONS",
    mineTotal
      ? `- ${plural(mineTotal, "coupon décidé", "coupons décidés")} : ${decided(r.mine)}.`
      : "- Aucun de vos coupons enregistrés n'a été décidé cette semaine.",
    "",
    "MON CARNET DE PARIS",
    ...(r.journal.bets
      ? [
        `- ${plural(r.journal.bets, "pari réglé", "paris réglés")} : ${
          decided({ won: r.journal.won, lost: r.journal.lost, void: r.journal.bets - r.journal.won - r.journal.lost }, [
            "passé",
            "passés",
          ])
        }.`,
        `- Mises : ${money(r.journal.staked)} ${currency} · Retour : ${money(r.journal.returned)} ${currency} · ` +
        `Bilan net : ${net > 0 ? "+" : net < 0 ? "−" : ""}${money(Math.abs(net))} ${currency}.`,
      ]
      : ["- Aucun pari réglé cette semaine dans votre carnet."]),
    "",
    "COUPONS DE LA PLATEFORME",
    pTotal
      ? `- ${plural(pTotal, "coupon décidé", "coupons décidés")} : ${decided(platform)}` +
        (pDecided ? ` (réussite ${Math.round((platform.won / pDecided) * 100)} %, annulés exclus).` : ".")
      : "- Aucun coupon de la plateforme décidé cette semaine.",
    ...(platform.won && platform.avg_won_odd ? [`- Cote moyenne des coupons gagnés : ${platform.avg_won_odd.toFixed(2).replace(".", ",")}.`] : []),
    "",
    "Les probabilités de Coupon Pro IA sont des estimations : les résultats passés ne préjugent pas des",
    "suivants. Coupon Pro IA n'est pas un bookmaker et ne prend aucun pari. Jouez avec modération.",
    "",
    "Vous recevez ce rapport parce que vous l'avez demandé. Pour l'arrêter : application → Profil →",
    "Notifications → Rapport hebdomadaire par e-mail.",
  ];
  return { subject: `Votre semaine Coupon Pro IA (${period})`, text: lines.join("\n") };
}
