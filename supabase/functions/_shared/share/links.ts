// Liens de partage : https://<projet>.supabase.co/functions/v1/share/c/<coupon> ou /share/m/<match>.
// Sur Android, redirection vers l'application (schéma couponproia://) ou, si elle n'est pas
// installée, vers le téléchargement de l'APK. Cibles fixes : aucune redirection ouverte.

export const ANDROID_PACKAGE = "com.couponproia.app";

export type ShareTarget = { kind: "coupon"; id: string } | { kind: "match"; id: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseShare(pathname: string): ShareTarget | null {
  const m = pathname.match(/\/share\/(c|m)\/([^/?#]+)\/?$/);
  if (!m) return null;
  if (m[1] === "c" && UUID.test(m[2])) return { kind: "coupon", id: m[2].toLowerCase() };
  if (m[1] === "m" && /^\d{1,12}$/.test(m[2])) return { kind: "match", id: m[2] };
  return null;
}

/** Chemin de l'écran dans l'application. */
export const appPath = (t: ShareTarget) => t.kind === "coupon" ? `/coupon/${t.id}` : `/match/${t.id}`;

/** Lien « intent » de Chrome : ouvre l'app, sinon la page de repli. */
export function intentUrl(t: ShareTarget, fallback: string): string {
  return `intent://open${appPath(t)}#Intent;scheme=couponproia;package=${ANDROID_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(fallback)};end`;
}

/** Téléchargement public de l'APK (stockage Supabase), ou l'adresse publiée si elle est publique. */
export function downloadUrl(projectUrl: string, published: string | null): string {
  if (published && published.includes("/storage/v1/object/public/")) return published;
  return `${projectUrl.replace(/\/$/, "")}/storage/v1/object/public/downloads/android/coupon-pro-ia-latest-arm64-v8a.apk`;
}

export const isAndroid = (ua: string | null) => /android/i.test(ua ?? "");
