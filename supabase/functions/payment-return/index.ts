// Page affichée par le navigateur après le paiement (retour de l'agrégateur).
// Elle ne valide rien : l'app vérifie elle-même le paiement auprès du serveur.
Deno.serve((req) => {
  const cancelled = new URL(req.url).searchParams.has("annule");
  const lines = cancelled
    ? [
      "Coupon Pro IA",
      "",
      "Paiement annulé : aucun montant n'a été prélevé.",
      "Revenez dans l'application pour réessayer quand vous le souhaitez.",
    ]
    : [
      "Coupon Pro IA",
      "",
      "Votre paiement a été transmis.",
      "Revenez dans l'application : votre abonnement ou vos crédits s'activent dès que l'opérateur confirme le paiement",
      "(en général en moins d'une minute).",
      "",
      "Vous pouvez fermer cette page.",
    ];
  return new Response(lines.join("\n"), { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8" } });
});
