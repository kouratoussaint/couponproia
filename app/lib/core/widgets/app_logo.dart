import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Emblème officiel (ballon + cerveau à circuits) suivi du nom « Coupon Pro IA ».
/// Pour les barres d'application et les écrans système.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.showName = true});

  /// Hauteur de l'emblème.
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emblem = Image.asset(
      'assets/brand/logo_emblem.webp',
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Coupon Pro IA',
    );
    if (!showName) return emblem;
    final style = GoogleFonts.montserrat(
      fontSize: size * 0.55,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      color: scheme.onSurface,
      letterSpacing: -0.5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        SizedBox(width: size * 0.2),
        Text.rich(
          TextSpan(
            text: 'Coupon Pro ',
            style: style,
            children: [
              TextSpan(text: 'IA', style: style.copyWith(color: scheme.primary))
            ],
          ),
        ),
      ],
    );
  }
}

/// Logo complet officiel, avec le nom dessiné. Pour les écrans d'accueil et de connexion.
class AppFullLogo extends StatelessWidget {
  const AppFullLogo({super.key, this.height = 140});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo_full.webp',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Coupon Pro IA',
    );
  }
}
