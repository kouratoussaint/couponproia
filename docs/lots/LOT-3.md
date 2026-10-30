# LOT 3 — Moteur d'analyse et « Analyser avec l'IA »

Statut au 30/10/2026 : **livré, déployé, évalué sur 2 210 matchs réels de la saison 2024/25.**
Le texte rédigé par l'IA s'active dès que le secret GitHub `GEMINI_API_KEY` est ajouté et Supabase
redéployé ; sans clé, l'analyse affiche la fiche statistique seule (aucun texte inventé à la place).

## 1. Résumé

- **Moteur statistique `poisson-1.0`** (côté serveur, fonctions pures testées) : buts attendus de
  chaque équipe à partir des seuls matchs joués **avant** le coup d'envoi (même compétition, même
  saison), forces « rétrécies » vers la moyenne (5 matchs fictifs) pour ne pas surréagir aux petits
  échantillons, matrice des scores, probabilités 1/N/2, double chance, plus/moins 0,5 à 3,5, les deux
  marquent, 3 scores les plus probables, classement recalculé à la date du match, forme, confrontations.
- **Comparaison au marché** : probabilité implicite de la cote médiane, marge des bookmakers retirée,
  écart modèle − marché en points.
- **Fiabilité** : faible / moyenne / bonne selon le nombre de matchs à domicile de l'équipe qui reçoit
  et à l'extérieur de l'équipe visiteuse (< 4, < 8, ≥ 8).
- **Couche IA** : l'IA reçoit la fiche et doit l'expliquer en français, sans rien ajouter.
  Fournisseur principal Gemini (Flash-Lite), secours Anthropic puis Groq si leurs clés existent.
- **Garde-fous** (une réponse non conforme est redemandée une fois, puis remplacée par la fiche seule) :
  1. structure JSON imposée ;
  2. chaque nombre écrit doit exister dans la fiche (tolérance d'arrondi) ;
  3. marchés proposés pris dans la fiche, probabilité remplacée par la valeur exacte du moteur ;
  4. mots interdits : sûr, garanti, assuré, certitude, imparable, infaillible, sans risque, gain, 100 % ;
  5. aucune recommandation si la fiabilité est faible ;
  6. aucun marché proposé dans une famille où le moteur ne bat pas la référence sur l'historique.
- **Cache et coûts** : une analyse est partagée entre utilisateurs (un match = un coût) ; 12 h pour un
  match à venir, définitive pour un match joué ; 20 nouvelles analyses par utilisateur et par jour ;
  chaque appel IA est journalisé (fournisseur, modèle, tokens, coût estimé, durée, erreur).
- **App** : bouton « Analyser avec l'IA » sur la fiche match ; probabilités en barres, buts attendus,
  scores probables, tableau modèle / marché, atouts, tendances, marchés envisageables, risques,
  informations manquantes, conclusion, version du moteur et du modèle, date. Pour un match joué :
  « Résultat réel … ; avant le match, le modèle donnait X % à cette issue ».
- **Administration** (menu latéral, permission `ai.configure`) : écran « Moteur d'analyse » avec la
  dernière évaluation, la calibration, le détail par compétition, le journal IA et son coût ; bouton
  de régénération d'une analyse.

## 2. Qualité mesurée (évaluation du 30/10/2026)

Méthode « marche avant » : chaque match terminé est prédit avec les seuls matchs antérieurs de sa
compétition (30 premiers matchs de chaque compétition non notés), puis comparé au résultat réel.
Référence : fréquences observées jusque-là dans la compétition. Brier et log-loss : plus bas = mieux.

| Marché | Brier moteur | Brier référence | Log-loss moteur | Log-loss référence | Issue la plus probable juste |
| --- | --- | --- | --- | --- | --- |
| 1 / N / 2 (2 210 matchs) | **0,614** | 0,647 | **1,024** | 1,063 | **50,1 %** (référence 44,0 %) |
| Plus de 2,5 buts | 0,498 | **0,494** | 0,693 | **0,688** | 56,1 % |
| Les deux marquent | 0,500 | **0,498** | 0,694 | **0,691** | 55,7 % |

- **1/N/2 : le moteur apporte de la valeur**, et il est bien calibré (annoncé 40–50 % → réalisé 46 % ;
  60–70 % → 64 % ; 70–80 % → 73 %).
- Par compétition, il bat la référence en Premier League, Liga, Serie A, Bundesliga, Ligue 1 et Ligue des
  champions CAF, **mais pas** en Ligue des champions ni en Ligue Europa UEFA (tours préliminaires et
  équipes de championnats différents, que le modèle ne compare pas).
- **Plus/moins et « les deux marquent » : pas mieux qu'une simple fréquence.** Conséquence appliquée
  tout de suite : l'IA ne peut pas proposer ces marchés, et l'app affiche un avertissement « Prudence ».
  L'amélioration est prévue au Laboratoire IA (LOT 6) : correction Dixon-Coles des petits scores,
  pondération des matchs récents, forces inter-compétitions pour les coupes européennes.
- L'évaluation est relancée automatiquement chaque lundi à 5 h 30 (UTC) et à la demande.

## 3. Migrations

7. `analysis_engine` : `ai_prompts` (versionnés, un seul actif), `match_analyses`, `ai_requests`,
   `engine_evaluations`, RLS (analyses et évaluations lisibles par tout utilisateur connecté, journal IA
   visible par son auteur et les gestionnaires, prompts réservés à `ai.configure`, écritures serveur),
   7 réglages privés `ai.*`, flag `match_analysis` activé, prompt v1.
8. `engine_schedule` : `app_private.invoke_engine_evaluation` (secret lu dans Vault) et tâche
   hebdomadaire `engine-evaluate-weekly`.
9. `prompt_v2` : consigne sur la qualité mesurée par famille de marchés ; v2 active.

Edge Functions : `analyze-match` (JWT obligatoire), `engine-evaluate` (administrateur ou secret cron).

## 4. Tests

| Suite | Résultat |
| --- | --- |
| SQL (PostgreSQL 16) : 30 + 16 + 11 tests (RLS du LOT 3) | **57/57** |
| Deno : moteur (matrice, marchés, rétrécissement, classement, cotes sans marge, fiche sans fuite, championnat synthétique battu par le modèle), IA (validation, nombres inventés, mots interdits sans faux positifs, correction puis succès, secours, repli, choix du modèle Gemini) | **32/32** |
| Flutter : analyse statique + tests (lecture des analyses, libellés, pourcentages, erreurs) | **réussis** en CI |
| Déploiement : 3 migrations, 5 fonctions, tâche hebdomadaire planifiée | **réussi** |
| Évaluation réelle déclenchée par pg_cron → pg_net → engine-evaluate | **réussie** (HTTP 200, 2 210 matchs) |

## 5. Réglages modifiables (table `app_settings`, privés)

| Clé | Valeur | Rôle |
| --- | --- | --- |
| `ai.provider` / `ai.model` | `gemini` / `gemini-3.5-flash-lite` | Fournisseur et modèle principaux (si le modèle n'existe pas, le Flash-Lite disponible le plus récent est choisi) |
| `ai.fallback_providers` / `ai.models` | `anthropic`, `groq` | Secours, utilisés seulement si leur clé est configurée |
| `ai.pricing_usd_per_mtok` | prix publics Gemini Flash-Lite | Estimation du coût ; modèle absent = coût non estimé |
| `ai.max_new_analyses_per_user_day` | 20 | Quota de nouvelles analyses |
| `ai.analysis_ttl_hours` | 12 | Validité d'une analyse d'un match à venir |

## 6. Limites connues

- Mode archive : tous les matchs sont joués ; les analyses sont donc des analyses **d'avant-match**
  (calculées sans connaître le score) suivies du résultat réel. Aucune cote en archive : le tableau
  modèle / marché apparaîtra avec les matchs à venir (offre Pro d'API-Football).
- Aucune donnée de compositions, blessures ou suspensions : signalé dans chaque analyse.
- Coupes européennes : le moteur ne voit que les matchs de la compétition elle-même.
- Le texte IA dépend du secret `GEMINI_API_KEY` (gratuit sur aistudio.google.com) ; l'offre gratuite
  de Google peut utiliser les données envoyées pour améliorer ses produits (ici : uniquement des
  statistiques de matchs publics, aucune donnée d'utilisateur).

## 7. Prochaine étape proposée

LOT 4 — Générateur de coupons (combinaison de sélections issues des analyses, contrôle des risques,
cote totale, mise indicative, historique), selon le plan validé.
