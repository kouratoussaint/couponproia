import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../analysis/data/analysis_format.dart';
import '../../coupons/data/coupon_models.dart';
import '../../matches/data/sports_format.dart';
import '../data/studio_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Visuel d'un coupon, dessiné à la taille exacte du format (1 px logique = 1 px exporté).
/// Tout ce qui est affiché vient du coupon : équipes, issues, cotes, horaires, résultat.
class CouponVisual extends StatelessWidget {
  const CouponVisual({super.key, required this.coupon, required this.options});

  final StudioCoupon coupon;
  final StudioOptions options;

  /// Taille des blocs fixes (en-tête, titre, total, mentions) selon la place disponible.
  static double densityFor(StudioFormat f) => switch (f) {
        StudioFormat.square => 0.78,
        StudioFormat.portrait => 0.9,
        StudioFormat.story => 1.1,
        StudioFormat.landscape => 0.85,
      };

  /// Nombre maximal de sélections affichées par format (au-delà : « + N autres sélections »).
  static int maxLinesFor(StudioFormat f) => switch (f) {
        StudioFormat.square => 4,
        StudioFormat.portrait => 6,
        StudioFormat.story => 12,
        StudioFormat.landscape => 7,
      };

  @override
  Widget build(BuildContext context) {
    final f = options.format;
    final p = _Palette.of(options);
    final content = f.isWide
        ? _Landscape(coupon: coupon, options: options, p: p)
        : _Portrait(coupon: coupon, options: options, p: p);
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: f.width,
          height: f.height,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Background(options: options, p: p),
                Padding(
                    padding: EdgeInsets.all(f.isWide ? 64 : 60),
                    child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Couleurs et polices par modèle
// ---------------------------------------------------------------------------------------------
class _Palette {
  const _Palette({
    required this.fg,
    required this.muted,
    required this.card,
    required this.cardBorder,
    required this.accent,
    required this.oddBg,
    required this.oddFg,
    required this.titleFont,
    required this.bodyFont,
    this.paper,
  });

  factory _Palette.of(StudioOptions o) {
    final primary = o.primary;
    final accent = o.accent;
    switch (o.template) {
      case 'clair':
        const ink = Color(0xFF14211B);
        return _Palette(
          fg: ink,
          muted: ink.withValues(alpha: 0.6),
          card: Colors.white,
          cardBorder: primary.withValues(alpha: 0.18),
          accent: primary,
          oddBg: primary,
          oddFg: Colors.white,
          titleFont: 'Montserrat',
          bodyFont: 'Inter',
        );
      case 'ticket':
        const ink = Color(0xFF1B1B1B);
        return _Palette(
          fg: ink,
          muted: ink.withValues(alpha: 0.55),
          card: Colors.transparent,
          cardBorder: Colors.transparent,
          accent: accent,
          oddBg: Colors.transparent,
          oddFg: ink,
          titleFont: 'Roboto Mono',
          bodyFont: 'Roboto Mono',
          paper: const Color(0xFFFFFCF5),
        );
      case 'stade':
        return _Palette(
          fg: Colors.white,
          muted: Colors.white.withValues(alpha: 0.72),
          card: Colors.black.withValues(alpha: 0.22),
          cardBorder: Colors.white.withValues(alpha: 0.14),
          accent: accent,
          oddBg: accent,
          oddFg: _onColor(accent),
          titleFont: 'Montserrat',
          bodyFont: 'Inter',
        );
      case 'prestige':
        return _Palette(
          fg: Colors.white,
          muted: Colors.white.withValues(alpha: 0.7),
          card: Colors.white.withValues(alpha: 0.07),
          cardBorder: accent.withValues(alpha: 0.45),
          accent: accent,
          oddBg: Colors.transparent,
          oddFg: accent,
          titleFont: 'Playfair Display',
          bodyFont: 'Inter',
        );
      default: // classique
        return _Palette(
          fg: Colors.white,
          muted: Colors.white.withValues(alpha: 0.66),
          card: Colors.white.withValues(alpha: 0.06),
          cardBorder: Colors.white.withValues(alpha: 0.10),
          accent: accent,
          oddBg: accent,
          oddFg: _onColor(accent),
          titleFont: 'Montserrat',
          bodyFont: 'Inter',
        );
    }
  }

  final Color fg;
  final Color muted;
  final Color card;
  final Color cardBorder;
  final Color accent;
  final Color oddBg;
  final Color oddFg;
  final String titleFont;
  final String bodyFont;

  /// Chaque graisse est demandée explicitement (google_fonts charge la vraie variante).
  TextStyle t(double size,
          {FontWeight w = FontWeight.w700,
          Color? color,
          FontStyle? style,
          double? height,
          double? spacing}) =>
      GoogleFonts.getFont(titleFont,
          fontSize: size,
          fontWeight: w,
          color: color ?? fg,
          fontStyle: style,
          height: height,
          letterSpacing: spacing);

  TextStyle b(double size,
          {FontWeight w = FontWeight.w400,
          Color? color,
          FontStyle? style,
          double? height,
          double? spacing}) =>
      GoogleFonts.getFont(bodyFont,
          fontSize: size,
          fontWeight: w,
          color: color ?? fg,
          fontStyle: style,
          height: height,
          letterSpacing: spacing);

  /// Fond « papier » du modèle Ticket.
  final Color? paper;
}

Color _onColor(Color c) =>
    c.computeLuminance() > 0.45 ? const Color(0xFF111111) : Colors.white;

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

// ---------------------------------------------------------------------------------------------
// Fond
// ---------------------------------------------------------------------------------------------
class _Background extends StatelessWidget {
  const _Background({required this.options, required this.p});

  final StudioOptions options;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final primary = options.primary;
    switch (options.template) {
      case 'clair':
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
                primary.withValues(alpha: 0.06), const Color(0xFFF7F8F6)),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(height: 18, color: primary),
          ),
        );
      case 'ticket':
        return ColoredBox(color: primary);
      case 'stade':
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primary, _darken(primary, 0.16)],
            ),
          ),
          child: CustomPaint(painter: _PitchPainter()),
        );
      case 'prestige':
        return Stack(
          fit: StackFit.expand,
          children: [
            if (options.cover != null)
              Image.memory(options.cover!, fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -0.8),
                    radius: 1.4,
                    colors: [Color.lerp(primary, Colors.white, 0.08)!, primary],
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black
                        .withValues(alpha: options.cover != null ? 0.55 : 0.1),
                    Colors.black
                        .withValues(alpha: options.cover != null ? 0.82 : 0.35),
                  ],
                ),
              ),
            ),
          ],
        );
      default:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_darken(primary, 0.22), _darken(primary, 0.32)],
            ),
          ),
        );
    }
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.025);
    final band = size.height / 10;
    for (var i = 0; i < 10; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, i * band, size.width, band), stripe);
    }
    canvas.drawRect(
        Rect.fromLTWH(30, 30, size.width - 60, size.height - 60), paint);
    canvas.drawLine(Offset(30, size.height / 2),
        Offset(size.width - 30, size.height / 2), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2),
        math.min(size.width, size.height) * 0.16, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------------------------
// Mises en page
// ---------------------------------------------------------------------------------------------
class _Portrait extends StatelessWidget {
  const _Portrait(
      {required this.coupon, required this.options, required this.p});

  final StudioCoupon coupon;
  final StudioOptions options;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final f = options.format;
    final d = CouponVisual.densityFor(f);
    final children = <Widget>[
      _Header(coupon: coupon, options: options, p: p, scale: d),
      SizedBox(height: 36 * d),
      _Title(coupon: coupon, p: p, scale: d),
      SizedBox(height: 28 * d),
      Expanded(
        child: _Lines(
            coupon: coupon,
            options: options,
            p: p,
            comfortable: switch (f) {
              StudioFormat.square => 3,
              StudioFormat.portrait => 4,
              _ => 7,
            }),
      ),
      SizedBox(height: 28 * d),
      _Total(coupon: coupon, options: options, p: p, scale: d),
      ..._texts(options, p, d),
      SizedBox(height: 24 * d),
      _Footer(options: options, p: p, scale: d),
    ];
    final column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return p.paper == null ? column : _Paper(p: p, child: column);
  }
}

class _Landscape extends StatelessWidget {
  const _Landscape(
      {required this.coupon, required this.options, required this.p});

  final StudioCoupon coupon;
  final StudioOptions options;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(coupon: coupon, options: options, p: p, scale: 0.85),
              const SizedBox(height: 36),
              _Title(coupon: coupon, p: p, scale: 0.95),
              const Spacer(),
              _Total(coupon: coupon, options: options, p: p, scale: 0.9),
              ..._texts(options, p, 0.85),
              const SizedBox(height: 20),
              _Footer(options: options, p: p, scale: 0.85),
            ],
          ),
        ),
        const SizedBox(width: 56),
        Expanded(
            child:
                _Lines(coupon: coupon, options: options, p: p, comfortable: 5)),
      ],
    );
    return p.paper == null ? row : _Paper(p: p, child: row);
  }
}

List<Widget> _texts(StudioOptions o, _Palette p, double scale) => [
      if (o.customText.trim().isNotEmpty) ...[
        SizedBox(height: 22 * scale),
        Text(
          o.customText.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: p.b(34 * scale, height: 1.25, w: FontWeight.w500),
        ),
      ],
      if ((o.signature ?? '').trim().isNotEmpty) ...[
        SizedBox(height: 14 * scale),
        Text(
          o.signature!.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: p.t(32 * scale,
              style: FontStyle.italic, color: p.accent, w: FontWeight.w600),
        ),
      ],
    ];

/// Fond papier du modèle Ticket, avec bord dentelé en haut et en bas.
class _Paper extends StatelessWidget {
  const _Paper({required this.p, required this.child});

  final _Palette p;
  final Widget child;

  @override
  Widget build(BuildContext context) => PhysicalShape(
        clipper: const _TicketClipper(),
        color: p.paper!,
        elevation: 12,
        shadowColor: Colors.black54,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 44, 44, 34), child: child),
      );
}

class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper();

  @override
  Path getClip(Size size) {
    const tooth = 18.0;
    final path = Path()..moveTo(0, tooth);
    var x = 0.0;
    var up = true;
    while (x < size.width) {
      x = math.min(size.width, x + tooth);
      path.lineTo(x, up ? 0 : tooth);
      up = !up;
    }
    path.lineTo(size.width, size.height - tooth);
    up = true;
    while (x > 0) {
      x = math.max(0, x - tooth);
      path.lineTo(x, up ? size.height : size.height - tooth);
      up = !up;
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ---------------------------------------------------------------------------------------------
// Blocs
// ---------------------------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header(
      {required this.coupon,
      required this.options,
      required this.p,
      required this.scale});

  final StudioCoupon coupon;
  final StudioOptions options;
  final _Palette p;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final name = (options.displayName ?? '').trim();
    final logoSize = (options.template == 'prestige' ? 110.0 : 88.0) * scale;
    final logo = options.logo != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.22),
            child: Image.memory(options.logo!,
                width: logoSize, height: logoSize, fit: BoxFit.cover),
          )
        : Image.asset('assets/brand/logo_emblem.webp',
            width: logoSize, height: logoSize);
    final d = coupon.firstKickoff;
    return Row(
      children: [
        logo,
        SizedBox(width: 24 * scale),
        Expanded(
          child: Text(
            name.isEmpty ? tr('Coupon Pro IA') : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: p.t(46 * scale, w: FontWeight.w800),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: 22 * scale, vertical: 10 * scale),
          decoration: BoxDecoration(
            border: Border.all(color: p.muted, width: 2),
            borderRadius: BorderRadius.circular(40),
          ),
          child: Text(
            '${_weekday(d)} ${shortDate(d)}',
            style: p.b(30 * scale, w: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.coupon, required this.p, required this.scale});

  final StudioCoupon coupon;
  final _Palette p;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final n = coupon.lines.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          coupon.title.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: p.t(66 * scale, w: FontWeight.w900, height: 1.05, spacing: 1),
        ),
        SizedBox(height: 10 * scale),
        Container(height: 8 * scale, width: 140 * scale, color: p.accent),
        SizedBox(height: 14 * scale),
        Text(trf('{0} sélection{1}', [n, n > 1 ? 's' : '']),
            style: p.b(32 * scale, color: p.muted, w: FontWeight.w600)),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines(
      {required this.coupon,
      required this.options,
      required this.p,
      required this.comfortable});

  final StudioCoupon coupon;
  final StudioOptions options;
  final _Palette p;
  final int comfortable;

  @override
  Widget build(BuildContext context) {
    final all = coupon.lines;
    final shown = all.take(CouponVisual.maxLinesFor(options.format)).toList();
    final hidden = all.length - shown.length;
    final gap = (options.template == 'ticket' ? 6.0 : 16.0) *
        (comfortable / math.max(shown.length, comfortable)).clamp(0.5, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final rows = shown.length + (hidden > 0 ? 0.5 : 0);
      final dashes =
          options.template == 'ticket' ? 10.0 * (shown.length - 1) : 0.0;
      final rowHeight =
          ((c.maxHeight - gap * (rows.ceil() - 1) - dashes) / rows)
              .clamp(30.0, 190.0);
      // La taille des textes suit la hauteur de ligne : rien ne peut déborder.
      final scale = (rowHeight / 165).clamp(0.2, 1.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            SizedBox(
              height: rowHeight,
              child: _LineCard(
                  line: shown[i], options: options, p: p, scale: scale),
            ),
            if (options.template == 'ticket' && i < shown.length - 1)
              _Dashes(color: p.muted),
          ],
          if (hidden > 0) ...[
            SizedBox(height: gap),
            SizedBox(
              height: rowHeight * 0.5,
              child: Center(
                child: Text(
                    trf('+ {0} autre{1} sélection{2}',
                        [hidden, hidden > 1 ? 's' : '', hidden > 1 ? 's' : '']),
                    style: p.b(30, color: p.muted)),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard(
      {required this.line,
      required this.options,
      required this.p,
      required this.scale});

  final StudioLine line;
  final StudioOptions options;
  final _Palette p;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final logos = options.showLogos;
    final resultColor = switch (line.result) {
      'won' => const Color(0xFF22C55E),
      'lost' => const Color(0xFFEF4444),
      _ => null,
    };
    final odd = Container(
      constraints: BoxConstraints(minWidth: 150 * s),
      padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 12 * s),
      decoration: BoxDecoration(
        color: p.oddBg,
        borderRadius: BorderRadius.circular(18 * s),
        border: p.oddBg == Colors.transparent
            ? Border.all(color: p.accent, width: 3)
            : null,
      ),
      child: Text(
        decimal(line.odd),
        textAlign: TextAlign.center,
        style: p.t(44 * s, w: FontWeight.w800, color: p.oddFg),
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 28 * s, vertical: 14 * s),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(26 * s),
        border: Border.all(
            color: resultColor ?? p.cardBorder,
            width: resultColor == null ? 2 : 4),
      ),
      child: Row(
        children: [
          if (logos) ...[
            _TeamStack(
                home: line.homeLogo,
                away: line.awayLogo,
                homeName: line.home,
                awayName: line.away,
                size: 64 * s,
                p: p),
            SizedBox(width: 22 * s),
          ],
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 680 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${line.competition} · ${timeLabel(line.kickoffAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: p.b(26 * s, color: p.muted),
                    ),
                    SizedBox(height: 4 * s),
                    Text(
                      '${line.home} – ${line.away}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: p.t(36 * s, w: FontWeight.w700),
                    ),
                    SizedBox(height: 4 * s),
                    Text(
                      line.pick,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: p.b(32 * s,
                          w: FontWeight.w600,
                          color: options.template == 'clair' ||
                                  options.template == 'ticket'
                              ? p.accent
                              : p.fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 18 * s),
          if (resultColor != null) ...[
            Icon(line.result == 'won' ? Icons.check_circle : Icons.cancel,
                color: resultColor, size: 48 * s),
            SizedBox(width: 12 * s),
          ],
          odd,
        ],
      ),
    );
  }
}

class _TeamStack extends StatelessWidget {
  const _TeamStack({
    required this.home,
    required this.away,
    required this.homeName,
    required this.awayName,
    required this.size,
    required this.p,
  });

  final String? home;
  final String? away;
  final String homeName;
  final String awayName;
  final double size;
  final _Palette p;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.75,
        height: size * 1.45,
        child: Stack(
          children: [
            Positioned(
                left: 0,
                top: 0,
                child: _TeamBadge(url: home, name: homeName, size: size, p: p)),
            Positioned(
                right: 0,
                bottom: 0,
                child: _TeamBadge(url: away, name: awayName, size: size, p: p)),
          ],
        ),
      );
}

/// Logo d'équipe (fournisseur de données) ou initiales si l'image manque.
class _TeamBadge extends StatelessWidget {
  const _TeamBadge(
      {required this.url,
      required this.name,
      required this.size,
      required _Palette p})
      : _p = p;

  final String? url;
  final String name;
  final double size;
  final _Palette _p;

  @override
  Widget build(BuildContext context) {
    // Initiales lisibles quel que soit le modèle (pastille toujours claire).
    final initials = Container(
      alignment: Alignment.center,
      decoration:
          const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE8ECEA)),
      child: Text(
        name.trim().isEmpty
            ? '?'
            : name
                .trim()
                .substring(0, math.min(2, name.trim().length))
                .toUpperCase(),
        style: _p.t(size * 0.34,
            w: FontWeight.w800, color: const Color(0xFF26332D)),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: size * 0.08)
        ],
      ),
      child: url == null
          ? initials
          : Image.network(url!,
              fit: BoxFit.contain, errorBuilder: (_, __, ___) => initials),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(
      {required this.coupon,
      required this.options,
      required this.p,
      required this.scale});

  final StudioCoupon coupon;
  final StudioOptions options;
  final _Palette p;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final result = coupon.result;
    final resultText = result == null
        ? null
        : '${resultLabels[result] ?? result}'
            '${result == 'won' && coupon.settledOdd != null ? trf(' · cote {0}', [
                    decimal(coupon.settledOdd!)
                  ]) : ''}';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 34 * s, vertical: 24 * s),
      decoration: BoxDecoration(
        color: p.paper != null ? Colors.transparent : p.card,
        borderRadius: BorderRadius.circular(28 * s),
        border: Border.all(color: p.accent, width: 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('COTE TOTALE'),
                    style: p.b(28 * s,
                        color: p.muted, w: FontWeight.w700, spacing: 2)),
                if (options.showProbability)
                  Padding(
                    padding: EdgeInsets.only(top: 8 * s),
                    child: Text(
                      trf('Probabilité estimée (modèle) : {0}',
                          [pct(coupon.combinedProbability)]),
                      style: p.b(26 * s, color: p.muted),
                    ),
                  ),
                if (resultText != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8 * s),
                    child: Text(
                      trf('Résultat : {0}', [resultText]),
                      style: p.b(30 * s,
                          w: FontWeight.w800,
                          color: result == 'won'
                              ? const Color(0xFF22C55E)
                              : result == 'lost'
                                  ? const Color(0xFFEF4444)
                                  : p.muted),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            decimal(coupon.totalOdd),
            style: p.t(104 * s, w: FontWeight.w900, color: p.accent, height: 1),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.options, required this.p, this.scale = 1});

  final StudioOptions options;
  final _Palette p;
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toujours sur une ligne, réduit si nécessaire : l'avertissement ne peut pas être coupé.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              studioDisclaimer,
              maxLines: 1,
              style: p.b(24 * scale, color: p.muted),
            ),
          ),
          if (options.watermark) ...[
            SizedBox(height: 10 * scale),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/brand/logo_emblem.webp',
                      width: 36 * scale, height: 36 * scale),
                  SizedBox(width: 10 * scale),
                  Text(tr('Réalisé avec Coupon Pro IA'),
                      style:
                          p.b(24 * scale, w: FontWeight.w700, color: p.muted)),
                ],
              ),
            ),
          ],
        ],
      );
}

class _Dashes extends StatelessWidget {
  const _Dashes({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, c) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              (c.maxWidth / 24).floor(),
              (_) => Container(
                  width: 12, height: 3, color: color.withValues(alpha: 0.5)),
            ),
          ),
        ),
      );
}

String _weekday(DateTime d) => [
      tr('Lun.'),
      tr('Mar.'),
      tr('Mer.'),
      tr('Jeu.'),
      tr('Ven.'),
      tr('Sam.'),
      tr('Dim.')
    ][d.weekday - 1];
