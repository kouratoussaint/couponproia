// Page d'arrivée des liens envoyés par Supabase Auth (site_url).
//
// Tant qu'aucun service d'envoi d'emails (SMTP) n'est branché, Supabase impose ses
// modèles par défaut, qui contiennent un lien au lieu d'un code à 6 chiffres. Ce lien
// confirme le compte puis redirige ici. Sur le domaine supabase.co, une Edge Function
// ne peut pas servir de HTML : on répond en texte simple, en anglais si le navigateur l'est.
import { browserLang } from "../_shared/lang.ts";

Deno.serve((req) => {
  const en = browserLang(req.headers.get("accept-language"), new URL(req.url).searchParams.get("lang")) === "en";
  const body = en
    ? "Coupon Pro IA\n\n" +
      "Done: your email address is confirmed.\n" +
      "Go back to the Coupon Pro IA app and sign in.\n\n" +
      "If the app shows an error message, ask for a new code."
    : "Coupon Pro IA\n\n" +
      "C'est fait : votre adresse e-mail est confirmée.\n" +
      "Retournez dans l'application Coupon Pro IA et connectez-vous.\n\n" +
      "Si un message d'erreur s'affiche dans l'application, demandez un nouveau code.";
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
});
