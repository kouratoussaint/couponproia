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
  /** Langue du profil (« fr » par défaut). */
  locale?: string;
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
  if (r.locale === "en") return weeklyEmailEn(r, platform, since, until, currency);
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

/** 12,500 */
export const moneyEn = (n: number) => Math.round(n).toLocaleString("en-US");
const pluralEn = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

function decidedEn(c: Counts, wonWord = "won"): string {
  const parts = [`${c.won} ${wonWord}`, `${c.lost} lost`];
  if (c.void) parts.push(`${c.void} void`);
  return parts.join(", ");
}

/** Même rapport, en anglais (profil réglé sur English). */
export function weeklyEmailEn(
  r: Recipient,
  platform: PlatformWeek,
  since: Date,
  until: Date,
  currency = "FCFA",
): { subject: string; text: string } {
  const period = `${day(since)} to ${day(until)}`;
  const mineTotal = r.mine.won + r.mine.lost + r.mine.void;
  const pDecided = platform.won + platform.lost;
  const pTotal = pDecided + platform.void;
  const net = r.journal.returned - r.journal.staked;
  const lines = [
    `Hello${r.name ? ` ${r.name}` : ""},`,
    "",
    `Here is your week on Coupon Pro IA (${period}), losses included.`,
    "",
    "MY COUPONS",
    mineTotal
      ? `- ${pluralEn(mineTotal, "coupon decided", "coupons decided")}: ${decidedEn(r.mine)}.`
      : "- None of your saved coupons was decided this week.",
    "",
    "MY BETTING LOG",
    ...(r.journal.bets
      ? [
        `- ${pluralEn(r.journal.bets, "bet settled", "bets settled")}: ${
          decidedEn({ won: r.journal.won, lost: r.journal.lost, void: r.journal.bets - r.journal.won - r.journal.lost })
        }.`,
        `- Stakes: ${moneyEn(r.journal.staked)} ${currency} · Return: ${moneyEn(r.journal.returned)} ${currency} · ` +
        `Net result: ${net > 0 ? "+" : net < 0 ? "−" : ""}${moneyEn(Math.abs(net))} ${currency}.`,
      ]
      : ["- No bet settled this week in your log."]),
    "",
    "PLATFORM COUPONS",
    pTotal
      ? `- ${pluralEn(pTotal, "coupon decided", "coupons decided")}: ${decidedEn(platform)}` +
        (pDecided ? ` (success ${Math.round((platform.won / pDecided) * 100)}%, void excluded).` : ".")
      : "- No platform coupon decided this week.",
    ...(platform.won && platform.avg_won_odd ? [`- Average odd of winning coupons: ${platform.avg_won_odd.toFixed(2)}.`] : []),
    "",
    "Coupon Pro IA probabilities are estimates: past results do not predict future ones.",
    "Coupon Pro IA is not a bookmaker and takes no bets. Play in moderation.",
    "",
    "You receive this report because you asked for it. To stop it: app → Profile →",
    "Notifications → Weekly report by email.",
  ];
  return { subject: `Your Coupon Pro IA week (${period})`, text: lines.join("\n") };
}
