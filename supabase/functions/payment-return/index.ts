// Page affichée par le navigateur après le paiement (retour de l'agrégateur).
// Elle ne valide rien : l'app vérifie elle-même le paiement auprès du serveur.
import { browserLang } from "../_shared/lang.ts";

Deno.serve((req) => {
  const url = new URL(req.url);
  const cancelled = url.searchParams.has("annule");
  const en = browserLang(req.headers.get("accept-language"), url.searchParams.get("lang")) === "en";
  const lines = en
    ? cancelled
      ? ["Coupon Pro IA", "", "Payment cancelled: no amount was charged.", "Go back to the app to try again whenever you like."]
      : [
        "Coupon Pro IA",
        "",
        "Your payment has been sent.",
        "Go back to the app: your plan or credits are activated as soon as the operator confirms the payment",
        "(usually in less than a minute).",
        "",
        "You can close this page.",
      ]
    : cancelled
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
