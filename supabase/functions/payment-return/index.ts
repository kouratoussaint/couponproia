// Page affichée par le navigateur après le paiement (retour de l'agrégateur).
// Elle ne valide rien : l'app vérifie elle-même le paiement auprès du serveur.
Deno.serve(() =>
  new Response(
    [
      "Coupon Pro IA",
      "",
      "Votre paiement a été transmis.",
      "Revenez dans l'application : votre abonnement ou vos crédits s'activent dès que l'opérateur confirme le paiement",
      "(en général en moins d'une minute).",
      "",
      "Vous pouvez fermer cette page.",
    ].join("\n"),
    { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8" } },
  )
);
