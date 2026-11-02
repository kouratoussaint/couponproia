import 'package:coupon_pro_ia/core/i18n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';

/// Toutes les opérations d'authentification passent par Supabase Auth.
/// Confirmation d'email et réinitialisation utilisent un code à 6 chiffres
/// envoyé par email : aucun lien à ouvrir, donc pas de dépendance aux liens profonds.
class AuthRepository {
  AuthRepository(this._auth);

  final GoTrueClient _auth;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Retourne `true` si une confirmation par code est nécessaire.
  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim(), 'locale': appLanguage},
    );
    return response.session == null;
  }

  Future<void> confirmSignUp(
      {required String email, required String code}) async {
    await _auth.verifyOTP(
        type: OtpType.signup, email: email.trim(), token: code.trim());
  }

  Future<void> resendSignUpCode(String email) async {
    await _auth.resend(type: OtpType.signup, email: email.trim());
  }

  Future<void> sendPasswordResetCode(String email) async {
    await _auth.resetPasswordForEmail(email.trim());
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    // Si le code a déjà été validé lors d'une tentative précédente (session ouverte),
    // on ne le revalide pas : il n'est utilisable qu'une fois.
    if (_auth.currentSession == null) {
      await _auth.verifyOTP(
          type: OtpType.recovery, email: email.trim(), token: code.trim());
    }
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider).auth),
);
