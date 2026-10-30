import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analysis/presentation/engine_admin_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/assistant/presentation/my_coupons_screen.dart';
import '../../features/auth/presentation/password_reset_screens.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/coupons/coupons_screen.dart';
import '../../features/coupons/presentation/coupon_detail_screen.dart';
import '../../features/coupons/presentation/generations_admin_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/lab/presentation/lab_screen.dart';
import '../../features/matches/presentation/competitions_screen.dart';
import '../../features/matches/presentation/match_detail_screen.dart';
import '../../features/matches/presentation/matches_screen.dart';
import '../../features/matches/presentation/sports_admin_screen.dart';
import '../../features/profile/presentation/legal_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/shell/swipe_branch_container.dart';
import '../../features/system/missing_config_screen.dart';
import '../providers.dart';
import 'app_routes.dart';

/// Décide où envoyer l'utilisateur. Fonction pure : testée unitairement.
String? resolveRedirect({
  required bool isConfigured,
  required bool isSignedIn,
  required String location,
}) {
  if (!isConfigured) {
    return location == AppRoutes.missingConfig ? null : AppRoutes.missingConfig;
  }
  final isPublic = AppRoutes.publicRoutes.contains(location);
  if (!isSignedIn) {
    return isPublic ? null : AppRoutes.signIn;
  }
  // Connecté : on quitte les écrans publics, sauf la saisie du nouveau mot de
  // passe (la validation du code ouvre la session avant la fin de l'écran).
  if (location == AppRoutes.missingConfig) return AppRoutes.home;
  if (isPublic && location != AppRoutes.resetPassword) return AppRoutes.home;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  final refresh = ValueNotifier<int>(0);
  StreamSubscription<Object>? subscription;
  if (config.isConfigured) {
    subscription = ref
        .read(supabaseClientProvider)
        .auth
        .onAuthStateChange
        .listen((_) => refresh.value++);
  }
  ref.onDispose(() {
    subscription?.cancel();
    refresh.dispose();
  });

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      isConfigured: config.isConfigured,
      isSignedIn: config.isConfigured &&
          ref.read(supabaseClientProvider).auth.currentSession != null,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.missingConfig,
        builder: (context, state) => const MissingConfigScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) =>
            VerifyEmailScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => ResetPasswordScreen(
            email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.matchDetail,
        builder: (context, state) => MatchDetailScreen(
            matchId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
      GoRoute(
        path: AppRoutes.competitions,
        builder: (context, state) => const CompetitionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.standings,
        builder: (context, state) => StandingsScreen(
            competitionId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
      GoRoute(
        path: AppRoutes.sportsAdmin,
        builder: (context, state) => const SportsAdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.generationsAdmin,
        builder: (context, state) => const GenerationsAdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.lab,
        builder: (context, state) =>
            LabScreen(initialCouponId: state.uri.queryParameters['coupon']),
      ),
      GoRoute(
        path: AppRoutes.myCoupons,
        builder: (context, state) => const MyCouponsScreen(),
      ),
      GoRoute(
        path: AppRoutes.myCouponDetail,
        builder: (context, state) =>
            MyCouponDetailScreen(couponId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.couponDetail,
        builder: (context, state) =>
            CouponDetailScreen(couponId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.engineAdmin,
        builder: (context, state) => const EngineAdminScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            SwipeBranchContainer(
          currentIndex: navigationShell.currentIndex,
          onPageChanged: (index) => navigationShell.goBranch(index),
          children: children,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.matches,
                builder: (context, state) => const MatchesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.coupons,
                builder: (context, state) => const CouponsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: AppRoutes.assistant,
                builder: (context, state) => const AssistantScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.profile,
              builder: (context, state) => const ProfileScreen(),
              routes: [
                GoRoute(
                    path: 'mentions',
                    builder: (context, state) => const LegalScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
