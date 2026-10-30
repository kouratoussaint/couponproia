import 'package:supabase_flutter/supabase_flutter.dart';

const _networkHints = [
  'socketexception',
  'failed host lookup',
  'network',
  'connection refused',
  'connection closed',
  'timed out',
  'clientexception',
];

bool _looksLikeNetwork(String text) {
  final lower = text.toLowerCase();
  return _networkHints.any(lower.contains);
}

/// Traduit une erreur technique en message clair, en français, pour l'utilisateur.
String userMessageFor(Object error) {
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Email ou mot de passe incorrect.';
      case 'email_not_confirmed':
        return 'Confirmez d’abord votre email avec le code reçu.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Un compte existe déjà avec cet email. Connectez-vous.';
      case 'weak_password':
        return 'Mot de passe trop faible : au moins 8 caractères, avec lettres et chiffres.';
      case 'same_password':
        return 'Choisissez un mot de passe différent de l’actuel.';
      case 'otp_expired':
        return 'Code invalide ou expiré. Demandez un nouveau code.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Trop de tentatives. Patientez quelques minutes avant de réessayer.';
      case 'signup_disabled':
        return 'Les inscriptions sont momentanément fermées.';
      case 'user_banned':
        return 'Ce compte est suspendu. Contactez le support.';
    }
    final message = error.message.toLowerCase();
    if (message.contains('invalid login'))
      return 'Email ou mot de passe incorrect.';
    if (message.contains('not confirmed'))
      return 'Confirmez d’abord votre email avec le code reçu.';
    if (message.contains('expired') ||
        (message.contains('invalid') && message.contains('token'))) {
      return 'Code invalide ou expiré. Demandez un nouveau code.';
    }
    if (_looksLikeNetwork(message))
      return 'Connexion internet indisponible. Réessayez.';
    return 'L’authentification a échoué. Réessayez.';
  }
  if (error is PostgrestException) {
    if (error.code == '42501') return 'Action non autorisée.';
    if (_looksLikeNetwork(error.message))
      return 'Connexion internet indisponible. Réessayez.';
    return 'Le serveur a refusé la demande. Réessayez plus tard.';
  }
  if (error is FunctionException) {
    return 'Le serveur n’a pas pu traiter la demande. Réessayez plus tard.';
  }
  if (_looksLikeNetwork(error.toString())) {
    return 'Connexion internet indisponible. Réessayez.';
  }
  return 'Une erreur inattendue est survenue. Réessayez.';
}
