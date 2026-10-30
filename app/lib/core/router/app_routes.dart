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
  static const legal = '/profil/mentions';

  static const publicRoutes = {signIn, signUp, verifyEmail, forgotPassword, resetPassword};

  static String verifyEmailFor(String email) =>
      Uri(path: verifyEmail, queryParameters: {'email': email}).toString();

  static String resetPasswordFor(String email) =>
      Uri(path: resetPassword, queryParameters: {'email': email}).toString();
}
