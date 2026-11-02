// Aide intégrée (D6) : articles courts, au vouvoiement, fidèles aux règles de l'application.
// {analysis_cost}, {lab_cost}, {assistant_cost} sont remplacés par les coûts réglés dans la
// console. Aucune promesse de résultat : les probabilités sont des estimations.
import '../../core/router/app_routes.dart';

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

const helpCategories = [
  'Bien démarrer',
  'Coupons IA',
  'Analyses et crédits',
  'Assistant, laboratoire et Mes coupons',
  'Suivre ses paris',
  'Forfaits et paiement',
  'Notifications, direct et widget',
  'Compte et sécurité',
];

const helpArticles = <HelpArticle>[
  // --- Bien démarrer -------------------------------------------------------------------------
  HelpArticle(
    id: 'principe',
    category: 'Bien démarrer',
    title: 'Comment fonctionne Coupon Pro IA ?',
    keywords: ['moteur', 'modèle', 'ia', 'bookmaker', 'estimation'],
    blocks: [
      'Coupon Pro IA analyse les matchs de football avec un moteur statistique : il estime la probabilité de chaque issue à partir des résultats réels (buts marqués et encaissés, à domicile et à l’extérieur), puis la compare aux cotes relevées chez les bookmakers.',
      'L’IA rédige ensuite une lecture du match à partir de ces chiffres. Elle n’invente aucune donnée : chaque chiffre vient de la fiche du moteur.',
      '• Les probabilités sont des estimations : un match peut toujours tourner autrement.',
      '• Coupon Pro IA n’est pas un bookmaker : aucun pari n’est pris dans l’application.',
      '• Tous les coupons publiés restent consultables, gagnés comme perdus (Performances).',
    ],
  ),
  HelpArticle(
    id: 'lire-chiffres',
    category: 'Bien démarrer',
    title: 'Lire une probabilité, une cote et un écart',
    keywords: ['probabilité', 'cote juste', 'écart', 'fiabilité', 'marge'],
    blocks: [
      '• Probabilité estimée : la chance d’une issue selon le moteur (par exemple 55 %).',
      '• Cote juste : 1 ÷ probabilité estimée. 55 % donne une cote juste de 1,82.',
      '• Cote du marché : la cote médiane des bookmakers relevée par l’application ; « max » est la meilleure cote relevée.',
      '• Écart : la différence entre l’estimation du moteur et celle du marché (marge du bookmaker retirée). Un écart positif ne prédit pas le résultat du match.',
      '• Fiabilité (faible, moyenne, bonne) : dépend du nombre de matchs déjà joués par les deux équipes cette saison.',
      'Une mention « Prudence » signale un type de marché où le moteur ne fait pas mieux qu’une simple fréquence sur l’historique ; « Marché récent » signale un marché pas encore évalué.',
    ],
  ),
  HelpArticle(
    id: 'marches',
    category: 'Bien démarrer',
    title: 'Les marchés de paris',
    keywords: [
      '1x2',
      'double chance',
      'plus de',
      'moins de',
      'btts',
      'remboursé',
      'dnb',
      'buts équipe'
    ],
    blocks: [
      '• Résultat (1X2) : victoire de l’équipe à domicile (1), nul (X) ou victoire de l’équipe à l’extérieur (2).',
      '• Double chance : deux issues sur trois (1X, 12 ou X2).',
      '• Plus / moins de buts : nombre total de buts au-dessus ou au-dessous d’une ligne (0,5 à 3,5).',
      '• Les deux équipes marquent : oui ou non.',
      '• Remboursé si nul : victoire d’une équipe ; en cas de match nul, la sélection est annulée (elle compte pour 1,00).',
      '• Buts de l’équipe à domicile ou à l’extérieur : plus ou moins de 0,5, 1,5 ou 2,5 buts pour une seule équipe.',
      'Tous les marchés se règlent sur le score à la fin du temps réglementaire (90 minutes et temps additionnel), sans prolongations ni tirs au but.',
    ],
  ),

  // --- Coupons IA -----------------------------------------------------------------------------
  HelpArticle(
    id: 'types-coupons',
    category: 'Coupons IA',
    title: 'Les types de coupons',
    keywords: [
      'coupon du jour',
      'prudent',
      'équilibré',
      'audacieux',
      'catégorie'
    ],
    blocks: [
      'Les coupons de la plateforme sont composés par le moteur parmi les vrais matchs cotés, selon des profils réglés par l’équipe : Coupon du jour, Prudent, Équilibré, Audacieux, Cote élevée, Multi-compétitions, Spécial compétition, Spécial marché, Stratégie.',
      '• Le Coupon du jour passe toujours par l’analyse IA de chaque match : une sélection qui contredirait cette analyse est écartée.',
      '• Le niveau de risque (Prudent, Équilibré, Audacieux) dépend de la probabilité estimée du coupon entier.',
      '• Un coupon publié n’est plus modifié : son résultat compte dans les performances, qu’il soit gagné ou perdu.',
    ],
    action: ('Voir les coupons', AppRoutes.coupons),
  ),
  HelpArticle(
    id: 'acces-coupons',
    category: 'Coupons IA',
    title: 'Quand puis-je voir les coupons ?',
    keywords: ['free', 'réservé', 'verrouillé', 'cadenas', 'après les matchs'],
    blocks: [
      '• Avec un forfait payant : tous les coupons, à tout moment, avant les matchs.',
      '• Avec le forfait FREE : les coupons et leurs sélections deviennent visibles après les matchs (2 h 15 après le coup d’envoi du dernier match du coupon). Avant, la ligne affiche « Réservé aux forfaits payants jusqu’à la fin des matchs ».',
      'Les résultats de tous les coupons restent consultables par tous dans l’onglet Résultats et dans Performances.',
    ],
    action: ('Voir les forfaits', AppRoutes.billing),
  ),
  HelpArticle(
    id: 'resultats',
    category: 'Coupons IA',
    title: 'Résultats : gagné, perdu, annulé',
    keywords: ['règlement', 'payé', 'terminé', 'reporté', 'annulé', 'void'],
    blocks: [
      '• Un coupon est perdu dès qu’une sélection est perdue.',
      '• Il est gagné quand toutes les sélections restantes sont gagnées ; une sélection annulée compte pour 1,00.',
      '• Il est annulé si toutes ses sélections sont annulées.',
      '• Un match annulé, abandonné ou attribué sur tapis vert annule la sélection ; un match reporté reste en attente, puis est annulé s’il n’est pas joué dans les 48 heures.',
      'Sur chaque ligne de Résultats : « Payé le … » pour un coupon gagné, « Terminé le … » pour un coupon perdu ou annulé.',
    ],
  ),

  // --- Analyses et crédits -------------------------------------------------------------------
  HelpArticle(
    id: 'analyser',
    category: 'Analyses et crédits',
    title: 'Analyser un match',
    keywords: [
      'analyser',
      'bouton',
      'rouge',
      'vert',
      'orange',
      'analyse offerte',
      'quota'
    ],
    blocks: [
      'Le bouton « Analyser » change de couleur selon vos droits :',
      '• Vert : l’analyse est possible (forfait payant, ou crédits suffisants avec le forfait FREE ; le coût est indiqué sur le bouton).',
      '• Rouge avec un cadenas : pas de forfait payant ni assez de crédits.',
      '• Orange « Voir l’analyse » : vous avez déjà obtenu cette analyse ; la consulter et la mettre à jour est gratuit.',
      'Avec le forfait FREE, une analyse coûte {analysis_cost}. Avec un forfait payant, elles sont incluses (dans la limite quotidienne du forfait).',
      'Chaque jour, une analyse est offerte à tous. Une analyse obtenue n’est visible que par vous.',
    ],
  ),
  HelpArticle(
    id: 'credits',
    category: 'Analyses et crédits',
    title: 'Les crédits IA',
    keywords: ['crédits', 'pack', 'acheter', 'solde', 'consommation'],
    blocks: [
      'Les crédits servent aux actions qui font travailler l’IA ou le moteur à votre demande. Le nombre de crédits est toujours affiché sur le bouton concerné.',
      '• Analyse d’un match avec le forfait FREE : {analysis_cost}.',
      '• Assistant IA (créer, modifier ou analyser un coupon, analyser des matchs) : {assistant_cost} par action réussie, quel que soit le forfait. Les questions sont gratuites.',
      '• Laboratoire avec le forfait FREE : {lab_cost} par calcul (analyser, optimiser, simuler, comparer). La composition manuelle reste gratuite.',
      'Chaque forfait comprend des crédits par mois ; vous pouvez aussi acheter des crédits seuls, sans abonnement. Votre solde est visible en haut du menu et dans Profil.',
    ],
    action: ('Acheter des crédits', AppRoutes.billing),
  ),

  // --- Assistant, laboratoire et Mes coupons -------------------------------------------------
  HelpArticle(
    id: 'assistant',
    category: 'Assistant, laboratoire et Mes coupons',
    title: 'Mon Assistant IA',
    keywords: ['assistant', 'conversation', 'demande', 'chat'],
    blocks: [
      'Décrivez le coupon voulu en langage courant : « 3 matchs, cote proche de 4, risque modéré », « un coupon prudent pour demain », « remplace les plus fragiles ».',
      'L’IA comprend la demande ; le moteur choisit les sélections parmi les vrais matchs cotés et vérifie tout. Vous gardez la main : enregistrer, modifier, analyser.',
      '• Une proposition, une modification ou une analyse réussie coûte {assistant_cost} ; les questions sont gratuites.',
      '• Les conversations sont dans l’historique (icône horloge).',
    ],
    action: ('Ouvrir l’assistant', AppRoutes.assistant),
  ),
  HelpArticle(
    id: 'laboratoire',
    category: 'Assistant, laboratoire et Mes coupons',
    title: 'Le Laboratoire',
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
      '• Composer : ouvrez un match et touchez une cote pour l’ajouter ; « Vérifier et enregistrer » relit les cotes et contrôle chaque match. Gratuit.',
      '• Analyser : sélections fragiles, risques, qualité des données.',
      '• Optimiser : propose des remplacements plus probables selon le modèle ; « Appliquer » crée une version optimisée (l’originale est conservée).',
      '• Simuler : la répartition des résultats possibles du coupon, sur des milliers de tirages (c’est une simulation).',
      '• Comparer : jusqu’à trois de vos coupons côte à côte.',
      'Avec le forfait FREE, chaque calcul coûte {lab_cost} ; il est gratuit avec un forfait payant.',
    ],
    action: ('Ouvrir le laboratoire', AppRoutes.assistantLab),
  ),
  HelpArticle(
    id: 'mes-coupons',
    category: 'Assistant, laboratoire et Mes coupons',
    title: 'Mes coupons',
    keywords: [
      'mes coupons',
      'renommer',
      'supprimer',
      'publier',
      'tipster',
      'bilan'
    ],
    blocks: [
      'Mes coupons regroupe les coupons enregistrés depuis l’assistant ou le laboratoire, avec votre bilan (gagnés, perdus, réussite, cote moyenne), pertes comprises.',
      '• Appui long ou ⋮ : ouvrir dans le laboratoire, simuler une mise, noter dans le carnet, partager, renommer, supprimer.',
      '• Publier sur votre profil Tipster rend le coupon visible par vos abonnés : il ne peut plus être modifié ni supprimé et son résultat compte dans vos statistiques.',
    ],
    action: ('Voir mes coupons', AppRoutes.assistantMyCoupons),
  ),

  // --- Suivre ses paris -----------------------------------------------------------------------
  HelpArticle(
    id: 'simulateur',
    category: 'Suivre ses paris',
    title: 'Simuler une mise',
    keywords: ['simulateur', 'mise', 'retour', 'prélèvement'],
    blocks: [
      'Depuis un match, un coupon ou une analyse, « Simuler une mise » calcule le retour selon la cote, la mise et l’éventuel prélèvement réglé, ainsi que la valeur moyenne estimée par le modèle.',
      'Ce n’est qu’un calcul : le résultat réel dépend du match.',
    ],
  ),
  HelpArticle(
    id: 'carnet',
    category: 'Suivre ses paris',
    title: 'Le carnet de paris',
    keywords: ['carnet', 'pari', 'mise', 'bilan', 'journal'],
    blocks: [
      'Le carnet garde la trace des paris que vous avez placés chez votre opérateur : mise, cote obtenue, sélections.',
      '• Le règlement est automatique, avec les mêmes règles que les coupons.',
      '• Le bilan du mois compte les mises, le retour et le bilan net, pertes comprises.',
      '• Un rappel peut vous prévenir 15 minutes avant le premier match d’un pari noté.',
    ],
    action: ('Ouvrir mon carnet', AppRoutes.journal),
  ),
  HelpArticle(
    id: 'bookmaker',
    category: 'Suivre ses paris',
    title: 'Reporter un coupon chez mon bookmaker',
    keywords: ['bookmaker', '1xbet', 'copier', 'code'],
    blocks: [
      '« Copier pour mon bookmaker » prépare le coupon ligne par ligne (date, affiche, code du pari, cote) pour le reporter sur le site de votre opérateur.',
      'Les cotes changent : vérifiez-les chez votre opérateur avant de valider. Coupon Pro IA ne place aucun pari.',
    ],
  ),

  // --- Forfaits et paiement ------------------------------------------------------------------
  HelpArticle(
    id: 'forfaits',
    category: 'Forfaits et paiement',
    title: 'Forfaits et paiement Mobile Money',
    keywords: [
      'forfait',
      'abonnement',
      'orange money',
      'moov',
      'paiement',
      'renouveler',
      'free'
    ],
    blocks: [
      'Les forfaits, leurs prix et leurs crédits sont détaillés dans Abonnement et crédits, en paiement mensuel ou annuel.',
      '• Paiement par Orange Money ou Moov Money, via un agrégateur agréé (LigdiCash ou CinetPay).',
      '• Le forfait ou les crédits sont activés après la confirmation de l’opérateur, vérifiée par notre serveur ; « Vérifier » relance le contrôle d’un paiement en attente.',
      '• Avant la fin d’un forfait, un rappel vous propose de le renouveler.',
      'Coupon Pro IA vend un service d’analyse : aucun pari n’est pris et aucun résultat n’est promis.',
    ],
    action: ('Voir les forfaits', AppRoutes.billing),
  ),

  // --- Notifications, direct et widget -------------------------------------------------------
  HelpArticle(
    id: 'notifications',
    category: 'Notifications, direct et widget',
    title: 'Notifications et heures calmes',
    keywords: ['notification', 'heures calmes', 'alerte', 'rapport', 'e-mail'],
    blocks: [
      'Profil → Notifications : choisissez ce que vous recevez (nouveaux coupons, résultats, rappels de match, scores en direct de vos paris, crédits…) et les heures calmes.',
      '• Rapport hebdomadaire par e-mail : le lundi matin, votre bilan de la semaine et celui des coupons de la plateforme (désactivé par défaut).',
      '• Les notifications restent aussi dans la boîte de réception (cloche de l’accueil).',
    ],
    action: ('Régler les notifications', AppRoutes.notificationSettings),
  ),
  HelpArticle(
    id: 'direct',
    category: 'Notifications, direct et widget',
    title: 'Les matchs en direct',
    keywords: ['direct', 'live', 'minute', 'score', 'actualiser'],
    blocks: [
      'Pendant un match, la minute, le score et le statut se mettent à jour tout seuls (environ toutes les 30 secondes), sur l’accueil, dans Matchs et dans la fiche du match. Tirer vers le bas reste possible mais n’est pas nécessaire.',
      'À chaque but ou fin de match, vos coupons et votre carnet sont relus. La mise à jour s’arrête quand l’application est en arrière-plan.',
    ],
  ),
  HelpArticle(
    id: 'widget',
    category: 'Notifications, direct et widget',
    title: 'Le widget de l’écran d’accueil',
    keywords: ['widget', 'écran d’accueil', 'raccourci'],
    blocks: [
      'Le widget affiche le Coupon du jour (cote, premier match ou résultat), le nombre de matchs du jour et en direct. Un toucher ouvre le coupon dans l’application.',
      '• Ajout : Profil → Apparence → « Widget sur l’écran d’accueil », ou appui long sur l’écran d’accueil du téléphone → Widgets → Coupon Pro IA.',
      '• Il se met à jour quand l’application est ouverte ; l’heure de mise à jour est indiquée en bas.',
    ],
  ),

  // --- Compte et sécurité ---------------------------------------------------------------------
  HelpArticle(
    id: 'compte',
    category: 'Compte et sécurité',
    title: 'Mon compte',
    keywords: ['profil', 'mot de passe', 'supprimer', 'déconnecter', 'données'],
    blocks: [
      '• Modifier votre nom ou votre photo : Profil → icône crayon.',
      '• Mot de passe oublié : depuis l’écran de connexion.',
      '• Supprimer votre compte : Profil → « Supprimer mon compte » (définitif).',
      '• Les rapports d’erreurs (activés par défaut) n’envoient aucun contenu personnel ; ils se coupent dans Profil → Apparence.',
    ],
    action: ('Ouvrir mon profil', AppRoutes.profile),
  ),
  HelpArticle(
    id: 'jeu-responsable',
    category: 'Compte et sécurité',
    title: 'Jouer avec modération',
    keywords: ['jeu responsable', 'budget', 'plafond', 'addiction', 'aide'],
    blocks: [
      'Fixez un budget mensuel et un plafond par pari : l’application vous alerte à 80 % puis à 100 % du budget, d’après votre carnet.',
      'Ne misez que ce que vous pouvez vous permettre de perdre. Si le jeu devient un problème, parlez-en à un proche ou à un professionnel de santé.',
    ],
    action: ('Jeu responsable', AppRoutes.responsibleGaming),
  ),
  HelpArticle(
    id: 'support',
    category: 'Compte et sécurité',
    title: 'Contacter le support',
    keywords: ['support', 'contact', 'problème', 'bug', 'question'],
    blocks: [
      'Une question ou un problème ? Profil → Aide → « Contacter le support » ouvre un e-mail adressé à l’équipe. Indiquez si possible la version de l’application (en bas du menu).',
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
