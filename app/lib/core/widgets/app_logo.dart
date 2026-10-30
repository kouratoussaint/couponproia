import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Logo Coupon Pro IA : pictogramme + nom (« IA » en vert).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = SvgPicture.asset(
      'assets/brand/logo_mark.svg',
      width: size,
      height: size,
      semanticsLabel: 'Coupon Pro IA',
    );
    if (!showName) return mark;
    final style = GoogleFonts.montserrat(
      fontSize: size * 0.55,
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
      letterSpacing: -0.5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.25),
        Text.rich(
          TextSpan(
            text: 'Coupon Pro ',
            style: style,
            children: [TextSpan(text: 'IA', style: style.copyWith(color: scheme.primary))],
          ),
        ),
      ],
    );
  }
}
