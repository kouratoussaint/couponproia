import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_colors.dart';

/// Thèmes clair et sombre. Typographie : Montserrat pour les titres,
/// Inter pour le texte courant.
abstract final class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.vertIA,
      brightness: Brightness.dark,
    ).copyWith(
      primary: BrandColors.vertIA,
      onPrimary: BrandColors.fondSombre,
      primaryContainer: BrandColors.vertProfond,
      onPrimaryContainer: BrandColors.vertIA,
      secondary: BrandColors.orange,
      onSecondary: BrandColors.fondSombre,
      tertiary: BrandColors.bleuTech,
      onTertiary: BrandColors.blanc,
      error: BrandColors.rouge,
      onError: BrandColors.blanc,
      surface: BrandColors.fondSombre,
      onSurface: BrandColors.blanc,
      onSurfaceVariant: const Color(0xFFB5C2BC),
      surfaceContainerLowest: BrandColors.fondSombre,
      surfaceContainerLow: BrandColors.vertProfond,
      surfaceContainer: BrandColors.surfaceSombre,
      surfaceContainerHigh: const Color(0xFF12302B),
      surfaceContainerHighest: const Color(0xFF173A34),
      outline: BrandColors.bordureSombre,
      outlineVariant: BrandColors.bordureSombre,
    );
    return _build(scheme, BrandColors.fondSombre);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.vertIA,
      brightness: Brightness.light,
    ).copyWith(
      primary: BrandColors.vertIAContraste,
      onPrimary: BrandColors.blanc,
      primaryContainer: const Color(0xFFD5F7E9),
      onPrimaryContainer: BrandColors.vertProfond,
      secondary: const Color(0xFFB7791F),
      onSecondary: BrandColors.blanc,
      tertiary: BrandColors.bleuTech,
      onTertiary: BrandColors.blanc,
      error: BrandColors.rouge,
      onError: BrandColors.blanc,
      surface: BrandColors.fondClair,
      onSurface: BrandColors.vertProfond,
      onSurfaceVariant: const Color(0xFF55635D),
      surfaceContainerLowest: BrandColors.blanc,
      surfaceContainerLow: BrandColors.blanc,
      surfaceContainer: BrandColors.blanc,
      surfaceContainerHigh: const Color(0xFFEDF1F4),
      surfaceContainerHighest: const Color(0xFFE4E9ED),
      outline: const Color(0xFFD3DBE0),
      outlineVariant: const Color(0xFFE4E9ED),
    );
    return _build(scheme, BrandColors.fondClair);
  }

  static ThemeData _build(ColorScheme scheme, Color background) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
    );
    final body = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = body
        .copyWith(
          displayLarge: GoogleFonts.montserrat(
              textStyle: body.displayLarge, fontWeight: FontWeight.w800),
          displayMedium: GoogleFonts.montserrat(
              textStyle: body.displayMedium, fontWeight: FontWeight.w800),
          displaySmall: GoogleFonts.montserrat(
              textStyle: body.displaySmall, fontWeight: FontWeight.w700),
          headlineLarge: GoogleFonts.montserrat(
              textStyle: body.headlineLarge, fontWeight: FontWeight.w700),
          headlineMedium: GoogleFonts.montserrat(
              textStyle: body.headlineMedium, fontWeight: FontWeight.w700),
          headlineSmall: GoogleFonts.montserrat(
              textStyle: body.headlineSmall, fontWeight: FontWeight.w700),
          titleLarge: GoogleFonts.montserrat(
              textStyle: body.titleLarge, fontWeight: FontWeight.w700),
          titleMedium: GoogleFonts.montserrat(
              textStyle: body.titleMedium, fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final radius = BorderRadius.circular(16);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        // Espace régulier entre deux cartes empilées (12 px), partout dans l'app.
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      // Barre du bas : sobre, fond plein, pastille discrète derrière l'icône active,
      // libellé en couleur de marque.
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 11.5,
            height: 1.2,
            letterSpacing: 0.1,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
