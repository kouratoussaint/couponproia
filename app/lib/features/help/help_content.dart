// Aide intégrée (D6) : articles courts, au vouvoiement, fidèles aux règles de l'application.
// {analysis_cost}, {lab_cost}, {assistant_cost} sont remplacés par les coûts réglés dans la
// console. Aucune promesse de résultat : les probabilités sont des estimations.
import '../../core/router/app_routes.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.category,
    required this.title,
    required this.blocks,
    this.keywords = const [],
    this.action,
  });

  final String id;
  final String category;
  final String title;

  /// Paragraphes ; une ligne qui commence par « • » est une puce.
  final List<String> blocks;
  final List<String> keywords;

  /// Bouton en bas de l'article : (libellé, page de l'app).
  final (String, String)? action;
}

final helpCategories = [
  tr('Bien démarrer'),
  tr('Coupons IA'),
  tr('Analyses et crédits'),
  tr('Assistant, laboratoire et Mes coupons'),
  tr('Suivre ses paris'),
  tr('Forfaits et paiement'),
  tr('Notifications, direct et widget'),
  tr('Compte et sécurité'),
];

final helpArticles = <HelpArticle>[
  // --- Bien démarrer -------------------------------------------------------------------------
  HelpArticle(
    id: 'principe',
    category: tr('Bien démarrer'),
    title: tr('Comment fonctionne Coupon Pro IA ?'),
    keywords: ['moteur', tr('modèle'), 'ia', 'bookmaker', 'estimation'],
    blocks: [
      tr('Coupon Pro IA analyse les matchs de football avec un moteur statistique : il estime la probabilité de chaque issue à partir des résultats réels (buts marqués et encaissés, à domicile et à l’extérieur), puis la compare aux cotes relevées chez les bookmakers.'),
      tr('L’IA rédige ensuite une lecture du match à partir de ces chiffres. Elle n’invente aucune donnée : chaque chiffre vient de la fiche du moteur.'),
      tr('• Les probabilités sont des estimations : un match peut toujours tourner autrement.'),
      tr('• Coupon Pro IA n’est pas un bookmaker : aucun pari n’est pris dans l’application.'),
      tr('• Tous les coupons publiés restent consultables, gagnés comme perdus (Performances).'),
    ],
  ),
  HelpArticle(
    id: 'lire-chiffres',
    category: tr('Bien démarrer'),
    title: tr('Lire une probabilité, une cote et un écart'),
    keywords: [
      tr('probabilité'),
      tr('cote juste'),
      tr('écart'),
      tr('fiabilité'),
      'marge'
    ],
    blocks: [
      tr('• Probabilité estimée : la chance d’une issue selon le moteur (par exemple 55 %).'),
      tr('• Cote juste : 1 ÷ probabilité estimée. 55 % donne une cote juste de 1,82.'),
      tr('• Cote du marché : la cote médiane des bookmakers relevée par l’application ; « max » est la meilleure cote relevée.'),
      tr('• Écart : la différence entre l’estimation du moteur et celle du marché (marge du bookmaker retirée). Un écart positif ne prédit pas le résultat du match.'),
      tr('• Fiabilité (faible, moyenne, bonne) : dépend du nombre de matchs déjà joués par les deux équipes cette saison.'),
      tr('Une mention « Prudence » signale un type de marché où le moteur ne fait pas mieux qu’une simple fréquence sur l’historique ; « Marché récent » signale un marché pas encore évalué.'),
    ],
  ),
  HelpArticle(
    id: 'marches',
    category: tr('Bien démarrer'),
    title: tr('Les marchés de paris'),
    keywords: [
      '1x2',
      tr('double chance'),
      tr('plus de'),
      tr('moins de'),
      'btts',
      tr('remboursé'),
      'dnb',
      tr('buts équipe')
    ],
    blocks: [
      tr('• Résultat (1X2) : victoire de l’équipe à domicile (1), nul (X) ou victoire de l’équipe à l’extérieur (2).'),
      tr('• Double chance : deux issues sur trois (1X, 12 ou X2).'),
      tr('• Plus / moins de buts : nombre total de buts au-dessus ou au-dessous d’une ligne (0,5 à 3,5).'),
      tr('• Les deux équipes marquent : oui ou non.'),
      tr('• Remboursé si nul : victoire d’une équipe ; en cas de match nul, la sélection est annulée (elle compte pour 1,00).'),
      tr('• Buts de l’équipe à domicile ou à l’extérieur : plus ou moins de 0,5, 1,5 ou 2,5 buts pour une seule équipe.'),
      tr('Tous les marchés se règlent sur le score à la fin du temps réglementaire (90 minutes et temps additionnel), sans prolongations ni tirs au but.'),
    ],
  ),

  // --- Coupons IA -----------------------------------------------------------------------------
  HelpArticle(
    id: 'types-coupons',
    category: tr('Coupons IA'),
    title: tr('Les types de coupons'),
    keywords: [
      tr('coupon du jour'),
      'prudent',
      tr('équilibré'),
      'audacieux',
      tr('catégorie')
    ],
    blocks: [
      tr('Les coupons de la plateforme sont composés par le moteur parmi les vrais matchs cotés, selon des profils réglés par l’équipe : Coupon du jour, Prudent, Équilibré, Audacieux, Cote élevée, Multi-compétitions, Spécial compétition, Spécial marché, Stratégie.'),
      tr('• Le Coupon du jour passe toujours par l’analyse IA de chaque match : une sélection qui contredirait cette analyse est écartée.'),
      tr('• Le niveau de risque (Prudent, Équilibré, Audacieux) dépend de la probabilité estimée du coupon entier.'),
      tr('• Un coupon publié n’est plus modifié : son résultat compte dans les performances, qu’il soit gagné ou perdu.'),
    ],
    action: (tr('Voir les coupons'), AppRoutes.coupons),
  ),
  HelpArticle(
    id: 'acces-coupons',
    category: tr('Coupons IA'),
    title: tr('Quand puis-je voir les coupons ?'),
    keywords: [
      'free',
      tr('réservé'),
      tr('verrouillé'),
      'cadenas',
      tr('après les matchs')
    ],
    blocks: [
      tr('• Avec un forfait payant : tous les coupons, à tout moment, avant les matchs.'),
      tr('• Avec le forfait FREE : les coupons et leurs sélections deviennent visibles après les matchs (2 h 15 après le coup d’envoi du dernier match du coupon). Avant, la ligne affiche « Réservé aux forfaits payants jusqu’à la fin des matchs ».'),
      tr('Les résultats de tous les coupons restent consultables par tous dans l’onglet Résultats et dans Performances.'),
    ],
    action: (tr('Voir les forfaits'), AppRoutes.billing),
  ),
  HelpArticle(
    id: 'resultats',
    category: tr('Coupons IA'),
    title: tr('Résultats : gagné, perdu, annulé'),
    keywords: [
      tr('règlement'),
      tr('payé'),
      tr('terminé'),
      tr('reporté'),
      tr('annulé'),
      'void'
    ],
    blocks: [
      tr('• Un coupon est perdu dès qu’une sélection est perdue.'),
      tr('• Il est gagné quand toutes les sélections restantes sont gagnées ; une sélection annulée compte pour 1,00.'),
      tr('• Il est annulé si toutes ses sélections sont annulées.'),
      tr('• Un match annulé, abandonné ou attribué sur tapis vert annule la sélection ; un match reporté reste en attente, puis est annulé s’il n’est pas joué dans les 48 heures.'),
      tr('Sur chaque ligne de Résultats : « Payé le … » pour un coupon gagné, « Terminé le … » pour un coupon perdu ou annulé.'),
    ],
  ),

  // --- Analyses et crédits -------------------------------------------------------------------
  HelpArticle(
    id: 'analyser',
    category: tr('Analyses et crédits'),
    title: tr('Analyser un match'),
    keywords: [
      'analyser',
      'bouton',
      'rouge',
      'vert',
      'orange',
      tr('analyse offerte'),
      'quota'
    ],
    blocks: [
      tr('Le bouton « Analyser » change de couleur selon vos droits :'),
      tr('• Vert : l’analyse est possible (forfait payant, ou crédits suffisants avec le forfait FREE ; le coût est indiqué sur le bouton).'),
      tr('• Rouge avec un cadenas : pas de forfait payant ni assez de crédits.'),
      tr('• Orange « Voir l’analyse » : vous avez déjà obtenu cette analyse ; la consulter et la mettre à jour est gratuit.'),
      tr('Avec le forfait FREE, une analyse coûte {analysis_cost}. Avec un forfait payant, elles sont incluses (dans la limite quotidienne du forfait).'),
      tr('Chaque jour, une analyse est offerte à tous. Une analyse obtenue n’est visible que par vous.'),
    ],
  ),
  HelpArticle(
    id: 'credits',
    category: tr('Analyses et crédits'),
    title: tr('Les crédits IA'),
    keywords: [tr('crédits'), 'pack', 'acheter', 'solde', 'consommation'],
    blocks: [
      tr('Les crédits servent aux actions qui font travailler l’IA ou le moteur à votre demande. Le nombre de crédits est toujours affiché sur le bouton concerné.'),
      tr('• Analyse d’un match avec le forfait FREE : {analysis_cost}.'),
      tr('• Assistant IA (créer, modifier ou analyser un coupon, analyser des matchs) : {assistant_cost} par action réussie, quel que soit le forfait. Les questions sont gratuites.'),
      tr('• Laboratoire avec le forfait FREE : {lab_cost} par calcul (analyser, optimiser, simuler, comparer). La composition manuelle reste gratuite.'),
      tr('Chaque forfait comprend des crédits par mois ; vous pouvez aussi acheter des crédits seuls, sans abonnement. Votre solde est visible en haut du menu et dans Profil.'),
    ],
    action: (tr('Acheter des crédits'), AppRoutes.billing),
  ),

  // --- Assistant, laboratoire et Mes coupons -------------------------------------------------
  HelpArticle(
    id: 'assistant',
    category: tr('Assistant, laboratoire et Mes coupons'),
    title: tr('Mon Assistant IA'),
    keywords: ['assistant', 'conversation', 'demande', 'chat'],
    blocks: [
      tr('Décrivez le coupon voulu en langage courant : « 3 matchs, cote proche de 4, risque modéré », « un coupon prudent pour demain », « remplace les plus fragiles ».'),
      tr('L’IA comprend la demande ; le moteur choisit les sélections parmi les vrais matchs cotés et vérifie tout. Vous gardez la main : enregistrer, modifier, analyser.'),
      tr('• Une proposition, une modification ou une analyse réussie coûte {assistant_cost} ; les questions sont gratuites.'),
      tr('• Les conversations sont dans l’historique (icône horloge).'),
    ],
    action: (tr('Ouvrir l’assistant'), AppRoutes.assistant),
  ),
  HelpArticle(
    id: 'laboratoire',
    category: tr('Assistant, laboratoire et Mes coupons'),
    title: tr('Le Laboratoire'),
    keywords: [
      'laboratoire',
      'labo',
      'composer',
      'optimiser',
      'simuler',
      'comparer',
      'manuel'
    ],
    blocks: [
      tr('• Composer : ouvrez un match et touchez une cote pour l’ajouter ; « Vérifier et enregistrer » relit les cotes et contrôle chaque match. Gratuit.'),
      tr('• Analyser : sélections fragiles, risques, qualité des données.'),
      tr('• Optimiser : propose des remplacements plus probables selon le modèle ; « Appliquer » crée une version optimisée (l’originale est conservée).'),
      tr('• Simuler : la répartition des résultats possibles du coupon, sur des milliers de tirages (c’est une simulation).'),
      tr('• Comparer : jusqu’à trois de vos coupons côte à côte.'),
      tr('Avec le forfait FREE, chaque calcul coûte {lab_cost} ; il est gratuit avec un forfait payant.'),
    ],
    action: (tr('Ouvrir le laboratoire'), AppRoutes.assistantLab),
  ),
  HelpArticle(
    id: 'mes-coupons',
    category: tr('Assistant, laboratoire et Mes coupons'),
    title: tr('Mes coupons'),
    keywords: [
      tr('mes coupons'),
      'renommer',
      'supprimer',
      'publier',
      'tipster',
      'bilan'
    ],
    blocks: [
      tr('Mes coupons regroupe les coupons enregistrés depuis l’assistant ou le laboratoire, avec votre bilan (gagnés, perdus, réussite, cote moyenne), pertes comprises.'),
      tr('• Appui long ou ⋮ : ouvrir dans le laboratoire, simuler une mise, noter dans le carnet, partager, renommer, supprimer.'),
      tr('• Publier sur votre profil Tipster rend le coupon visible par vos abonnés : il ne peut plus être modifié ni supprimé et son résultat compte dans vos statistiques.'),
    ],
    action: (tr('Voir mes coupons'), AppRoutes.assistantMyCoupons),
  ),

  // --- Suivre ses paris -----------------------------------------------------------------------
  HelpArticle(
    id: 'simulateur',
    category: tr('Suivre ses paris'),
    title: tr('Simuler une mise'),
    keywords: ['simulateur', 'mise', 'retour', tr('prélèvement')],
    blocks: [
      tr('Depuis un match, un coupon ou une analyse, « Simuler une mise » calcule le retour selon la cote, la mise et l’éventuel prélèvement réglé, ainsi que la valeur moyenne estimée par le modèle.'),
      tr('Ce n’est qu’un calcul : le résultat réel dépend du match.'),
    ],
  ),
  HelpArticle(
    id: 'carnet',
    category: tr('Suivre ses paris'),
    title: tr('Le carnet de paris'),
    keywords: ['carnet', 'pari', 'mise', 'bilan', 'journal'],
    blocks: [
      tr('Le carnet garde la trace des paris que vous avez placés chez votre opérateur : mise, cote obtenue, sélections.'),
      tr('• Le règlement est automatique, avec les mêmes règles que les coupons.'),
      tr('• Le bilan du mois compte les mises, le retour et le bilan net, pertes comprises.'),
      tr('• Un rappel peut vous prévenir 15 minutes avant le premier match d’un pari noté.'),
    ],
    action: (tr('Ouvrir mon carnet'), AppRoutes.journal),
  ),
  HelpArticle(
    id: 'bookmaker',
    category: tr('Suivre ses paris'),
    title: tr('Reporter un coupon chez mon bookmaker'),
    keywords: ['bookmaker', '1xbet', 'copier', 'code'],
    blocks: [
      tr('« Copier pour mon bookmaker » prépare le coupon ligne par ligne (date, affiche, code du pari, cote) pour le reporter sur le site de votre opérateur.'),
      tr('Les cotes changent : vérifiez-les chez votre opérateur avant de valider. Coupon Pro IA ne place aucun pari.'),
    ],
  ),

  // --- Forfaits et paiement ------------------------------------------------------------------
  HelpArticle(
    id: 'forfaits',
    category: tr('Forfaits et paiement'),
    title: tr('Forfaits et paiement Mobile Money'),
    keywords: [
      'forfait',
      'abonnement',
      tr('orange money'),
      'moov',
      'paiement',
      'renouveler',
      'free'
    ],
    blocks: [
      tr('Les forfaits, leurs prix et leurs crédits sont détaillés dans Abonnement et crédits, en paiement mensuel ou annuel.'),
      tr('• Paiement par Orange Money ou Moov Money, via un agrégateur agréé (LigdiCash ou CinetPay).'),
      tr('• Le forfait ou les crédits sont activés après la confirmation de l’opérateur, vérifiée par notre serveur ; « Vérifier » relance le contrôle d’un paiement en attente.'),
      tr('• Avant la fin d’un forfait, un rappel vous propose de le renouveler.'),
      tr('Coupon Pro IA vend un service d’analyse : aucun pari n’est pris et aucun résultat n’est promis.'),
    ],
    action: (tr('Voir les forfaits'), AppRoutes.billing),
  ),

  // --- Notifications, direct et widget -------------------------------------------------------
  HelpArticle(
    id: 'notifications',
    category: tr('Notifications, direct et widget'),
    title: tr('Notifications et heures calmes'),
    keywords: [
      'notification',
      tr('heures calmes'),
      'alerte',
      'rapport',
      'e-mail'
    ],
    blocks: [
      tr('Profil → Notifications : choisissez ce que vous recevez (nouveaux coupons, résultats, rappels de match, scores en direct de vos paris, crédits…) et les heures calmes.'),
      tr('• Rapport hebdomadaire par e-mail : le lundi matin, votre bilan de la semaine et celui des coupons de la plateforme (désactivé par défaut).'),
      tr('• Les notifications restent aussi dans la boîte de réception (cloche de l’accueil).'),
    ],
    action: (tr('Régler les notifications'), AppRoutes.notificationSettings),
  ),
  HelpArticle(
    id: 'direct',
    category: tr('Notifications, direct et widget'),
    title: tr('Les matchs en direct'),
    keywords: ['direct', 'live', 'minute', 'score', 'actualiser'],
    blocks: [
      tr('Pendant un match, la minute, le score et le statut se mettent à jour tout seuls (environ toutes les 30 secondes), sur l’accueil, dans Matchs et dans la fiche du match. Tirer vers le bas reste possible mais n’est pas nécessaire.'),
      tr('À chaque but ou fin de match, vos coupons et votre carnet sont relus. La mise à jour s’arrête quand l’application est en arrière-plan.'),
    ],
  ),
  HelpArticle(
    id: 'widget',
    category: tr('Notifications, direct et widget'),
    title: tr('Le widget de l’écran d’accueil'),
    keywords: ['widget', tr('écran d’accueil'), 'raccourci'],
    blocks: [
      tr('Le widget affiche le Coupon du jour (cote, premier match ou résultat), le nombre de matchs du jour et en direct. Un toucher ouvre le coupon dans l’application.'),
      tr('• Ajout : Profil → Apparence → « Widget sur l’écran d’accueil », ou appui long sur l’écran d’accueil du téléphone → Widgets → Coupon Pro IA.'),
      tr('• Il se met à jour quand l’application est ouverte ; l’heure de mise à jour est indiquée en bas.'),
    ],
  ),

  // --- Compte et sécurité ---------------------------------------------------------------------
  HelpArticle(
    id: 'compte',
    category: tr('Compte et sécurité'),
    title: tr('Mon compte'),
    keywords: [
      'profil',
      tr('mot de passe'),
      'supprimer',
      tr('déconnecter'),
      tr('données')
    ],
    blocks: [
      tr('• Modifier votre nom ou votre photo : Profil → icône crayon.'),
      tr('• Mot de passe oublié : depuis l’écran de connexion.'),
      tr('• Supprimer votre compte : Profil → « Supprimer mon compte » (définitif).'),
      tr('• Les rapports d’erreurs (activés par défaut) n’envoient aucun contenu personnel ; ils se coupent dans Profil → Apparence.'),
    ],
    action: (tr('Ouvrir mon profil'), AppRoutes.profile),
  ),
  HelpArticle(
    id: 'jeu-responsable',
    category: tr('Compte et sécurité'),
    title: tr('Jouer avec modération'),
    keywords: [tr('jeu responsable'), 'budget', 'plafond', 'addiction', 'aide'],
    blocks: [
      tr('Fixez un budget mensuel et un plafond par pari : l’application vous alerte à 80 % puis à 100 % du budget, d’après votre carnet.'),
      tr('Ne misez que ce que vous pouvez vous permettre de perdre. Si le jeu devient un problème, parlez-en à un proche ou à un professionnel de santé.'),
    ],
    action: (tr('Jeu responsable'), AppRoutes.responsibleGaming),
  ),
  HelpArticle(
    id: 'support',
    category: tr('Compte et sécurité'),
    title: tr('Contacter le support'),
    keywords: ['support', 'contact', tr('problème'), 'bug', 'question'],
    blocks: [
      tr('Une question ou un problème ? Profil → Aide → « Contacter le support » ouvre un e-mail adressé à l’équipe. Indiquez si possible la version de l’application (en bas du menu).'),
    ],
  ),
];

/// Article par identifiant.
HelpArticle? helpArticle(String id) =>
    helpArticles.where((a) => a.id == id).firstOrNull;

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll('’', "'");

/// Recherche dans les titres, mots-clés et textes (casse et accents ignorés).
List<HelpArticle> searchHelp(String query) {
  final q = _fold(query.trim());
  if (q.length < 2) return helpArticles;
  final words = q.split(RegExp(r'\s+'));
  int score(HelpArticle a) {
    final title = _fold(a.title);
    final keys = _fold(a.keywords.join(' '));
    final body = _fold(a.blocks.join(' '));
    var s = 0;
    for (final w in words) {
      if (title.contains(w)) {
        s += 3;
      } else if (keys.contains(w)) {
        s += 2;
      } else if (body.contains(w)) {
        s += 1;
      } else {
        return 0;
      }
    }
    return s;
  }

  final scored = [
    for (final a in helpArticles)
      if (score(a) > 0) (a, score(a))
  ]..sort((x, y) => y.$2.compareTo(x.$2));
  return [for (final (a, _) in scored) a];
}

/// Remplace les coûts réglés dans la console.
String fillCosts(String text,
        {required String analysis,
        required String lab,
        required String assistant}) =>
    text
        .replaceAll('{analysis_cost}', analysis)
        .replaceAll('{lab_cost}', lab)
        .replaceAll('{assistant_cost}', assistant);
