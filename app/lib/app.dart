import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/offline/offline_banner.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/text_scale_controller.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/widgets/root_messenger.dart';

class CouponProApp extends ConsumerWidget {
  const CouponProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Coupon Pro IA',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          AppTextScale(child: OfflineBanner(child: child)),
    );
  }
}
