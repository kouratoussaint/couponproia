/// Chemins de navigation de l'application.
abstract final class AppRoutes {
  // Accès public (non connecté)
  static const signIn = '/connexion';
  static const signUp = '/inscription';
  static const verifyEmail = '/verification';
  static const forgotPassword = '/mot-de-passe-oublie';
  static const resetPassword = '/nouveau-mot-de-passe';

  // Système
  static const missingConfig = '/configuration';

  // Onglets (connecté)
  static const home = '/accueil';
  static const matches = '/matchs';
  static const coupons = '/coupons';
  static const assistant = '/assistant';
  static const profile = '/profil';
  static const profileEdit = '/profil/modifier';

  /// Mentions légales et documents : plein écran (lot 27).
  static const legal = '/mentions';

  /// Anciennes adresses, redirigées (notifications déjà envoyées).
  static const oldLegal = '/profil/mentions';
  static const oldLab = '/laboratoire';
  static const oldMyCoupons = '/mes-coupons';
  static const oldCompetitions = '/competitions';

  /// Documents légaux : lisibles connecté ou non.
  static const legalDocument = '/documents/:code';
  static String legalDocumentFor(String code) => '/documents/$code';
  static bool isOpenRoute(String location) =>
      location.startsWith('/documents/');

  // Écrans plein écran (au-dessus des onglets)
  static const matchDetail = '/match/:id';
  static const standings = '/competitions/:id';
  static const sportsAdmin = '/admin/donnees';
  static const engineAdmin = '/admin/moteur';
  static const generationsAdmin = '/admin/generations';
  static const couponDetail = '/coupon/:id';

  static String couponDetailFor(String id) => '/coupon/$id';
  static const couponEdit = '/coupon/:id/modifier';
  static String couponEditFor(String id) => '/coupon/$id/modifier';
  static const performance = '/performances';
  static const billing = '/abonnement';
  static const studio = '/studio';
  static const studioBranding = '/studio/identite';
  static const studioEditor = '/studio/:kind/:id';

  static String studioFor(String kind, String id) => '/studio/$kind/$id';
  static const responsibleGaming = '/jeu-responsable';
  static const journal = '/carnet';
  static const notifications = '/notifications';
  static const notificationSettings = '/notifications/reglages';
  static const community = '/communaute';
  static const search = '/recherche';
  static const help = '/aide';
  static const helpArticle = '/aide/:id';
  static String helpArticleFor(String id) => '/aide/$id';

  /// Onglets ouverts directement depuis le menu latéral.
  static const matchesCompetitions = '/matchs?onglet=competitions';
  static const assistantMyCoupons = '/assistant?onglet=coupons';
  static const assistantLab = '/assistant?onglet=laboratoire';
  static const myTipsterProfile = '/communaute/mon-profil';
  static const tipster = '/tipster/:id';
  static const post = '/publication/:id';
  static const moderation = '/admin/moderation';
  static const blockedUsers = '/bloques';
  static const favoriteTeams = '/equipes-suivies';

  static String tipsterFor(String id) => '/tipster/$id';
  static const adminConsole = '/admin';
  static const adminUsers = '/admin/utilisateurs';
  static const adminUser = '/admin/utilisateurs/:id';
  static const adminFlags = '/admin/modules';
  static const adminSettings = '/admin/reglages';
  static const adminPayments = '/admin/paiements';
  static const adminPromos = '/admin/promos';
  static const adminCosts = '/admin/couts';
  static const adminAi = '/admin/ia';
  static const adminFeatured = '/admin/analyse-offerte';
  static const adminHealth = '/admin/sante';
  static const adminGrowth = '/admin/conversion';
  static const adminCampaigns = '/admin/notifications';
  static const adminLegal = '/admin/documents';
  static const adminAudit = '/admin/journal';

  static String adminUserFor(String id) => '/admin/utilisateurs/$id';
  static String postFor(int id) => '/publication/$id';
  static const myCouponDetail = '/mes-coupons/:id';

  static String myCouponFor(String id) => '/mes-coupons/$id';

  /// Laboratoire (onglet de l'Assistant IA), éventuellement sur un coupon enregistré.
  static String labFor(String? couponId) => couponId == null
      ? assistantLab
      : Uri(
          path: assistant,
          queryParameters: {'onglet': 'laboratoire', 'coupon': couponId},
        ).toString();

  static String matchDetailFor(int id) => '/match/$id';
  static String standingsFor(int id) => '/competitions/$id';

  static const publicRoutes = {
    signIn,
    signUp,
    verifyEmail,
    forgotPassword,
    resetPassword
  };

  static String verifyEmailFor(String email) =>
      Uri(path: verifyEmail, queryParameters: {'email': email}).toString();

  static String resetPasswordFor(String email) =>
      Uri(path: resetPassword, queryParameters: {'email': email}).toString();
}
