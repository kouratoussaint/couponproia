/// Validateurs de formulaires. Le serveur revérifie toujours (contraintes SQL, Supabase Auth).
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
  static final _otp = RegExp(r'^\d{6}$');

  static const minPasswordLength = 8;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Saisissez votre adresse e-mail.';
    if (!_email.hasMatch(v)) return 'Adresse e-mail invalide.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Saisissez un mot de passe.';
    if (v.length < minPasswordLength) {
      return 'Au moins $minPasswordLength caractères.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Utilisez des lettres et au moins un chiffre.';
    }
    return null;
  }

  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Au moins 2 caractères.';
    if (v.length > 40) return '40 caractères maximum.';
    return null;
  }

  static String? otpCode(String? value) {
    final v = value?.trim() ?? '';
    if (!_otp.hasMatch(v)) return 'Le code contient 6 chiffres.';
    return null;
  }
}
