// Page d'arrivée des liens envoyés par Supabase Auth (site_url).
//
// Tant qu'aucun service d'envoi d'emails (SMTP) n'est branché, Supabase impose ses
// modèles par défaut, qui contiennent un lien au lieu d'un code à 6 chiffres. Ce lien
// confirme le compte puis redirige ici. Sur le domaine supabase.co, une Edge Function
// ne peut pas servir de HTML : on répond en texte simple.
Deno.serve(() =>
  new Response(
    "Coupon Pro IA\n\n" +
      "C'est fait : votre adresse e-mail est confirmée.\n" +
      "Retournez dans l'application Coupon Pro IA et connectez-vous.\n\n" +
      "Si un message d'erreur s'affiche dans l'application, demandez un nouveau code.",
    { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } },
  )
);
