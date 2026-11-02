import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Validateurs de formulaires. Le serveur revérifie toujours (contraintes SQL, Supabase Auth).
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
  static final _otp = RegExp(r'^\d{6}$');

  static const minPasswordLength = 8;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return tr('Saisissez votre adresse e-mail.');
    if (!_email.hasMatch(v)) return tr('Adresse e-mail invalide.');
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return tr('Saisissez un mot de passe.');
    if (v.length < minPasswordLength) {
      return trf('Au moins {0} caractères.', [minPasswordLength]);
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return tr('Utilisez des lettres et au moins un chiffre.');
    }
    return null;
  }

  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return tr('Au moins 2 caractères.');
    if (v.length > 40) return tr('40 caractères maximum.');
    return null;
  }

  static String? otpCode(String? value) {
    final v = value?.trim() ?? '';
    if (!_otp.hasMatch(v)) return tr('Le code contient 6 chiffres.');
    return null;
  }
}
