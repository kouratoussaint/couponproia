// Edge Function publique : ouverture d'un lien partagé (coupon ou match). Sur Android, redirige vers
// l'application ou, si elle n'est pas installée, vers le téléchargement de l'APK ; ailleurs, un court
// texte. Chaque ouverture est comptée (type, cible, Android ou non) pour le tableau de conversion.
import { serverContext } from "../_shared/http.ts";
import { downloadUrl, intentUrl, isAndroid, parseShare } from "../_shared/share/links.ts";

Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("Méthode non autorisée", { status: 405 });
  const target = parseShare(new URL(req.url).pathname);
  const text = (body: string, status = 200) =>
    new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  if (!target) return text("Lien Coupon Pro IA invalide ou expiré.", 404);

  const ctx = serverContext();
  const projectUrl = Deno.env.get("SUPABASE_URL") ?? "";
  let published: string | null = null;
  if (ctx) {
    const { data } = await ctx.db.from("app_versions").select("download_url")
      .eq("platform", "android").order("build_number", { ascending: false }).limit(1).maybeSingle();
    published = (data?.download_url as string | undefined) ?? null;
    if (req.method === "GET") {
      await ctx.db.from("share_clicks").insert({
        kind: target.kind,
        target: target.id,
        android: isAndroid(req.headers.get("user-agent")),
      });
    }
  }
  const download = downloadUrl(projectUrl, published);
  if (isAndroid(req.headers.get("user-agent"))) {
    return new Response(null, { status: 302, headers: { Location: intentUrl(target, download), "Cache-Control": "no-store" } });
  }
  return text([
    "Coupon Pro IA",
    "",
    `Ce ${target.kind === "coupon" ? "coupon" : "match"} s'ouvre dans l'application Coupon Pro IA (Android).`,
    "Ouvrez ce lien depuis votre téléphone Android, ou installez l'application :",
    download,
    "",
    "Estimations, aucune certitude. 18+ · Pariez de façon responsable.",
  ].join("\n"));
});
