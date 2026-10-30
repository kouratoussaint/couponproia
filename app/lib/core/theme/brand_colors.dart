import 'package:flutter/material.dart';

/// Palette officielle de Coupon Pro IA (charte du LOT 0).
abstract final class BrandColors {
  static const vertIA = Color(0xFF00D084);
  static const vertProfond = Color(0xFF0A1F1A);
  static const bleuTech = Color(0xFF0E1B4D);
  static const fondSombre = Color(0xFF071B1B);
  static const fondClair = Color(0xFFF4F7FA);
  static const blanc = Color(0xFFFFFFFF);
  static const gris = Color(0xFF82918A);
  static const orange = Color(0xFFE5A43B);
  static const rouge = Color(0xFFD94C4C);

  /// Vert assombri pour le texte et les boutons sur fond clair : le vert IA
  /// sur blanc n'atteint pas le contraste minimal de lisibilité (WCAG AA).
  static const vertIAContraste = Color(0xFF00875A);

  /// Surfaces dérivées pour le mode sombre (cartes, champs).
  static const surfaceSombre = Color(0xFF0D2622);
  static const bordureSombre = Color(0xFF1C3A34);
}
