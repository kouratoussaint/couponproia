import 'package:coupon_pro_ia/core/config/app_config.dart';
import 'package:coupon_pro_ia/core/errors/error_messages.dart';
import 'package:coupon_pro_ia/core/router/app_router.dart';
import 'package:coupon_pro_ia/core/router/app_routes.dart';
import 'package:coupon_pro_ia/core/theme/theme_mode_controller.dart';
import 'package:coupon_pro_ia/core/validators.dart';
import 'package:coupon_pro_ia/features/system/system_providers.dart';
import 'package:coupon_pro_ia/features/system/update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('awa@exemple.bf'), isNull);
      expect(Validators.email(' awa@exemple.bf '), isNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('awa@'), isNotNull);
      expect(Validators.email('awa exemple.bf'), isNotNull);
    });

    test('mot de passe : 8 caractères, lettres et chiffre', () {
      expect(Validators.password('abcdefg1'), isNull);
      expect(Validators.password('abc1'), isNotNull);
      expect(Validators.password('abcdefgh'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
    });

    test('nom affiché entre 2 et 40 caractères', () {
      expect(Validators.displayName('Awa'), isNull);
      expect(Validators.displayName(' A '), isNotNull);
      expect(Validators.displayName('x' * 41), isNotNull);
    });

    test('code OTP à 6 chiffres', () {
      expect(Validators.otpCode('123456'), isNull);
      expect(Validators.otpCode('12345'), isNotNull);
      expect(Validators.otpCode('12a456'), isNotNull);
    });
  });

  group('Redirections', () {
    test('sans configuration, tout mène à l’écran de configuration', () {
      expect(
        resolveRedirect(
            isConfigured: false, isSignedIn: false, location: AppRoutes.home),
        AppRoutes.missingConfig,
      );
      expect(
        resolveRedirect(
            isConfigured: false,
            isSignedIn: false,
            location: AppRoutes.missingConfig),
        isNull,
      );
    });

    test('non connecté : seuls les écrans publics sont accessibles', () {
      expect(
        resolveRedirect(
            isConfigured: true, isSignedIn: false, location: AppRoutes.profile),
        AppRoutes.signIn,
      );
      expect(
        resolveRedirect(
            isConfigured: true, isSignedIn: false, location: AppRoutes.signUp),
        isNull,
      );
    });

    test(
        'connecté : les écrans publics renvoient à l’accueil, sauf le nouveau mot de passe',
        () {
      expect(
        resolveRedirect(
            isConfigured: true, isSignedIn: true, location: AppRoutes.signIn),
        AppRoutes.home,
      );
      expect(
        resolveRedirect(
            isConfigured: true,
            isSignedIn: true,
            location: AppRoutes.resetPassword),
        isNull,
      );
      expect(
        resolveRedirect(
            isConfigured: true, isSignedIn: true, location: AppRoutes.legal),
        isNull,
      );
    });

    test('les liens vers la vérification transportent l’email', () {
      expect(AppRoutes.verifyEmailFor('awa@exemple.bf'),
          '/verification?email=awa%40exemple.bf');
    });
  });

  group('Thème', () {
    test('aller-retour nom <-> mode', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeFromName(themeModeToName(mode)), mode);
      }
      expect(themeModeFromName(null), ThemeMode.system);
      expect(themeModeFromName('rose'), ThemeMode.system);
    });
  });

  group('Mises à jour', () {
    const latest = AppVersionInfo(
      versionName: '0.2.0',
      buildNumber: 20,
      minSupportedBuild: 10,
      releaseNotes: 'Matchs réels',
    );

    test('aucune mise à jour si à jour ou si rien n’est publié', () {
      expect(
          updateKindFor(installedBuild: 20, latest: latest), UpdateKind.none);
      expect(updateKindFor(installedBuild: 5, latest: null), UpdateKind.none);
    });

    test('optionnelle puis obligatoire sous le minimum supporté', () {
      expect(updateKindFor(installedBuild: 15, latest: latest),
          UpdateKind.optional);
      expect(updateKindFor(installedBuild: 9, latest: latest),
          UpdateKind.required);
    });

    test('message', () {
      expect(updateMessage(UpdateKind.optional, latest), 'Matchs réels');
      expect(updateMessage(UpdateKind.required, latest),
          contains('n’est plus prise en charge'));
    });
  });

  group('Messages d’erreur', () {
    test('identifiants incorrects', () {
      expect(
        userMessageFor(AuthException('Invalid login credentials',
            code: 'invalid_credentials')),
        'Email ou mot de passe incorrect.',
      );
    });

    test('réseau', () {
      expect(
        userMessageFor(Exception('SocketException: Failed host lookup')),
        'Connexion internet indisponible. Réessayez.',
      );
    });

    test('jamais de message technique brut', () {
      expect(userMessageFor(StateError('boom')),
          'Une erreur inattendue est survenue. Réessayez.');
    });
  });

  group('Configuration', () {
    test('une URL https et une clé sont exigées', () {
      expect(
        const AppConfig(
                supabaseUrl: '', supabaseAnonKey: '', environment: 'dev')
            .isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(
                supabaseUrl: 'https://x.supabase.co',
                supabaseAnonKey: 'k',
                environment: 'prod')
            .isConfigured,
        isTrue,
      );
    });
  });
}
