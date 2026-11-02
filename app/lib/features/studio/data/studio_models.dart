import 'dart:typed_data';
import 'dart:ui';

import '../../analysis/data/analysis_format.dart';
import '../../assistant/data/assistant_models.dart';
import '../../coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Formats d'export (pixels).
enum StudioFormat {
  square('Carré', 'square', 1080, 1080),
  portrait('Portrait', 'portrait', 1080, 1350),
  story('Story', 'story', 1080, 1920),
  landscape('Paysage', 'landscape', 1920, 1080);

  const StudioFormat(this._label, this.code, this.width, this.height);

  final String _label;
  String get label => tr(_label);
  final String code;
  final double width;
  final double height;

  Size get size => Size(width, height);
  bool get isTall => height / width >= 1.6;
  bool get isWide => width > height;
}

enum StudioFileType { png, jpg, pdf }

/// Mots interdits sur un visuel (mêmes règles que le serveur et l'IA).
final RegExp forbiddenWords = RegExp(
  r'(?<![\p{L}\p{N}])(sûr(e|s|es)?|sûrement|garanti(e|es|s|r|t)?|assuré(e|s|es)?|certitudes?|'
  r'imparables?|infaillibles?|sans risque|gains?|100\s?%)(?![\p{L}\p{N}])',
  caseSensitive: false,
  unicode: true,
);

String? forbiddenWordIn(String? text) =>
    text == null ? null : forbiddenWords.firstMatch(text)?.group(0);

/// « #0E7C47 » → couleur (null si invalide).
Color? parseHexColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class StudioTemplate {
  const StudioTemplate({
    required this.code,
    required this.name,
    required this.description,
    required this.minPlan,
    required this.available,
    required this.primary,
    required this.accent,
  });

  factory StudioTemplate.fromJson(Map<String, dynamic> j) {
    final d = j['defaults'] is Map
        ? Map<String, dynamic>.from(j['defaults'] as Map)
        : const <String, dynamic>{};
    return StudioTemplate(
      code: j['code'] as String,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      minPlan: j['min_plan'] as String? ?? 'FREE',
      available: j['available'] == true,
      primary:
          parseHexColor(d['primary'] as String?) ?? const Color(0xFF0E7C47),
      accent: parseHexColor(d['accent'] as String?) ?? const Color(0xFFF2C230),
    );
  }

  final String code;
  final String name;
  final String description;
  final String minPlan;
  final bool available;
  final Color primary;
  final Color accent;
}

/// Droits du studio pour l'utilisateur connecté (fonction my_studio).
class StudioRights {
  const StudioRights({
    required this.enabled,
    required this.plan,
    required this.branding,
    required this.watermark,
    required this.exportsToday,
    required this.templates,
    this.exportsPerDay,
  });

  factory StudioRights.fromJson(Map<String, dynamic> j) => StudioRights(
        enabled: j['enabled'] == true,
        plan: j['plan'] as String? ?? 'FREE',
        branding: j['branding'] as String? ?? 'none',
        watermark: j['watermark'] != false,
        exportsPerDay: (j['exports_per_day'] as num?)?.toInt(),
        exportsToday: (j['exports_today'] as num?)?.toInt() ?? 0,
        templates: [
          for (final t in (j['templates'] as List? ?? const []))
            StudioTemplate.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
      );

  final bool enabled;
  final String plan;

  /// none / name / full
  final String branding;
  final bool watermark;
  final int? exportsPerDay;
  final int exportsToday;
  final List<StudioTemplate> templates;

  bool get canName => branding == 'name' || branding == 'full';
  bool get canFull => branding == 'full';
  int? get remaining => exportsPerDay == null
      ? null
      : (exportsPerDay! - exportsToday).clamp(0, 1 << 30);
}

/// Identité visuelle (Tipster).
class Branding {
  const Branding({
    this.displayName,
    this.primaryColor,
    this.accentColor,
    this.signature,
    this.logoPath,
    this.coverPath,
  });

  factory Branding.fromJson(Map<String, dynamic> j) => Branding(
        displayName: j['display_name'] as String?,
        primaryColor: j['primary_color'] as String?,
        accentColor: j['accent_color'] as String?,
        signature: j['signature'] as String?,
        logoPath: j['logo_path'] as String?,
        coverPath: j['cover_path'] as String?,
      );

  final String? displayName;
  final String? primaryColor;
  final String? accentColor;
  final String? signature;
  final String? logoPath;
  final String? coverPath;

  Map<String, dynamic> toJson() => {
        'display_name': _blank(displayName),
        'primary_color': primaryColor,
        'accent_color': accentColor,
        'signature': _blank(signature),
        'logo_path': logoPath,
        'cover_path': coverPath,
      };

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

/// Une ligne du visuel : uniquement des données vérifiées du coupon.
class StudioLine {
  const StudioLine({
    required this.home,
    required this.away,
    required this.competition,
    required this.kickoffAt,
    required this.pick,
    required this.odd,
    this.homeLogo,
    this.awayLogo,
    this.result,
  });

  factory StudioLine.fromSelection(CouponSelection s) => StudioLine(
        home: s.match.home,
        away: s.match.away,
        homeLogo: s.match.homeLogo,
        awayLogo: s.match.awayLogo,
        competition: s.match.competition,
        kickoffAt: s.match.kickoffAt,
        pick: outcomeKeyLabel(s.key, s.match.home, s.match.away),
        odd: s.odd,
        result: s.result,
      );

  final String home;
  final String away;
  final String? homeLogo;
  final String? awayLogo;
  final String competition;
  final DateTime kickoffAt;
  final String pick;
  final double odd;
  final String? result;
}

/// Coupon prêt à mettre en forme (coupon de la plateforme ou coupon enregistré).
class StudioCoupon {
  const StudioCoupon({
    required this.sourceKind,
    required this.sourceId,
    required this.title,
    required this.totalOdd,
    required this.combinedProbability,
    required this.lines,
    this.result,
    this.settledOdd,
  });

  factory StudioCoupon.fromPlatform(Coupon c) => StudioCoupon(
        sourceKind: 'platform',
        sourceId: c.id,
        title: c.title,
        totalOdd: c.totalOdd,
        combinedProbability: c.combinedProbability,
        lines: [for (final s in c.selections) StudioLine.fromSelection(s)],
        result: c.isWithdrawn ? null : c.result,
        settledOdd: c.settledOdd,
      );

  factory StudioCoupon.fromUser(UserCoupon c) => StudioCoupon(
        sourceKind: 'user',
        sourceId: c.id,
        title: c.title,
        totalOdd: c.totalOdd,
        combinedProbability: c.combinedProbability,
        lines: [for (final s in c.selections) StudioLine.fromSelection(s)],
        result: c.result,
        settledOdd: c.settledOdd,
      );

  final String sourceKind;
  final String sourceId;
  final String title;
  final double totalOdd;
  final double combinedProbability;
  final List<StudioLine> lines;
  final String? result;
  final double? settledOdd;

  DateTime get firstKickoff =>
      lines.map((l) => l.kickoffAt).reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Réglages d'un visuel.
class StudioOptions {
  const StudioOptions({
    required this.template,
    required this.format,
    required this.primary,
    required this.accent,
    this.showProbability = true,
    this.showLogos = true,
    this.customText = '',
    this.watermark = true,
    this.displayName,
    this.signature,
    this.logo,
    this.cover,
  });

  final String template;
  final StudioFormat format;
  final Color primary;
  final Color accent;
  final bool showProbability;
  final bool showLogos;
  final String customText;
  final bool watermark;
  final String? displayName;
  final String? signature;

  /// Octets des images de l'utilisateur (déjà téléchargées).
  final Uint8List? logo;
  final Uint8List? cover;
}

final studioDisclaimer = tr(
    'Estimations, aucun gain garanti. Interdit aux moins de 18 ans. Pariez de façon responsable.');
