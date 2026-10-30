// Créneaux de génération programmée, en heure locale (réglage app.timezone).

/** Décalage du fuseau à l'instant donné (ms) : heure locale = UTC + décalage. */
export function tzOffsetMs(at: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(at);
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
  const asUtc = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
  return asUtc - Math.floor(at.getTime() / 1000) * 1000;
}

export function localDate(at: Date, timeZone: string): string {
  return new Date(at.getTime() + tzOffsetMs(at, timeZone)).toISOString().slice(0, 10);
}

export interface Slot {
  slotKey: string;
  slotAt: Date;
}

/**
 * Créneaux échus : heure du jour (locale) passée depuis moins de `catchUpMinutes`.
 * Le rattrapage couvre une exécution planifiée manquée ; la clé rend chaque créneau unique.
 */
export function dueSlots(times: string[], now: Date, timeZone: string, catchUpMinutes = 60): Slot[] {
  const offset = tzOffsetMs(now, timeZone);
  const out: Slot[] = [];
  for (const day of [0, -1]) {
    const local = new Date(now.getTime() + offset + day * 86400_000);
    const date = local.toISOString().slice(0, 10);
    for (const t of times) {
      const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(t);
      if (!m) continue;
      const slotAt = new Date(Date.parse(`${date}T${t}:00Z`) - offset);
      const age = now.getTime() - slotAt.getTime();
      if (age >= 0 && age < catchUpMinutes * 60_000) out.push({ slotKey: `${date} ${t}`, slotAt });
    }
  }
  return out;
}
