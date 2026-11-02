import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

final _networkHints = [
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
        return tr('E-mail ou mot de passe incorrect.');
      case 'email_not_confirmed':
        return tr('Confirmez d’abord votre adresse e-mail avec le code reçu.');
      case 'user_already_exists':
      case 'email_exists':
        return tr(
            'Un compte existe déjà avec cette adresse e-mail. Connectez-vous.');
      case 'weak_password':
        return tr(
            'Mot de passe trop faible : au moins 8 caractères, avec lettres et chiffres.');
      case 'same_password':
        return tr('Choisissez un mot de passe différent de l’actuel.');
      case 'otp_expired':
        return tr('Code invalide ou expiré. Demandez un nouveau code.');
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return tr(
            'Trop de tentatives. Patientez quelques minutes avant de réessayer.');
      case 'signup_disabled':
        return tr('Les inscriptions sont momentanément fermées.');
      case 'user_banned':
        return tr('Ce compte est suspendu. Contactez le support.');
    }
    final message = error.message.toLowerCase();
    if (message.contains('invalid login')) {
      return tr('E-mail ou mot de passe incorrect.');
    }
    if (message.contains('not confirmed')) {
      return tr('Confirmez d’abord votre adresse e-mail avec le code reçu.');
    }
    if (message.contains('expired') ||
        (message.contains('invalid') && message.contains('token'))) {
      return tr('Code invalide ou expiré. Demandez un nouveau code.');
    }
    if (_looksLikeNetwork(message)) {
      return tr('Connexion internet indisponible. Réessayez.');
    }
    return tr('L’authentification a échoué. Réessayez.');
  }
  if (error is PostgrestException) {
    if (error.code == '42501') return tr('Action non autorisée.');
    if (_looksLikeNetwork(error.message)) {
      return tr('Connexion internet indisponible. Réessayez.');
    }
    return tr('Le serveur a refusé la demande. Réessayez plus tard.');
  }
  if (error is FunctionException) {
    return tr('Le serveur n’a pas pu traiter la demande. Réessayez plus tard.');
  }
  if (_looksLikeNetwork(error.toString())) {
    return tr('Connexion internet indisponible. Réessayez.');
  }
  return tr('Une erreur inattendue est survenue. Réessayez.');
}
