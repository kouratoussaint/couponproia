// Boutons pleins à code couleur : vert (action possible), rouge (verrouillé ou
// déconnexion), orange (déjà obtenu, suppression). Contraste lisible en clair et sombre.
import 'package:flutter/material.dart';

import 'brand_colors.dart';

enum SolidTone { green, red, orange }

({Color bg, Color fg}) solidColors(BuildContext context, SolidTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    SolidTone.green => dark
        ? (bg: BrandColors.vertIA, fg: BrandColors.vertProfond)
        : (bg: BrandColors.vertIAContraste, fg: Colors.white),
    SolidTone.red => (bg: const Color(0xFFC0392B), fg: Colors.white),
    SolidTone.orange => (bg: BrandColors.orange, fg: const Color(0xFF2B1A00)),
  };
}

ButtonStyle solidButtonStyle(BuildContext context, SolidTone tone,
    {bool compact = false}) {
  final c = solidColors(context, tone);
  return FilledButton.styleFrom(
    backgroundColor: c.bg,
    foregroundColor: c.fg,
    visualDensity: compact ? VisualDensity.compact : null,
    padding: compact ? const EdgeInsets.symmetric(horizontal: 10) : null,
  );
}

ButtonStyle solidIconButtonStyle(BuildContext context, SolidTone tone) {
  final c = solidColors(context, tone);
  return IconButton.styleFrom(backgroundColor: c.bg, foregroundColor: c.fg);
}
