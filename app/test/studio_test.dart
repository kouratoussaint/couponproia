import 'dart:typed_data';

import 'package:coupon_pro_ia/features/studio/data/studio_export.dart';
import 'package:coupon_pro_ia/features/studio/data/studio_models.dart';
import 'package:coupon_pro_ia/features/studio/presentation/coupon_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

StudioCoupon _coupon(int n, {String? result}) => StudioCoupon(
      sourceKind: 'platform',
      sourceId: 'c1',
      title: 'Coupon du jour',
      totalOdd: 4.25,
      combinedProbability: 0.31,
      result: result,
      settledOdd: result == 'won' ? 4.25 : null,
      lines: [
        for (var i = 0; i < n; i++)
          StudioLine(
            home: 'Borussia Mönchengladbach $i',
            away: 'Wolverhampton Wanderers',
            competition: 'Premier League',
            kickoffAt: DateTime(2026, 10, 31, 15 + i % 6, 30),
            pick: 'Victoire Borussia Mönchengladbach $i',
            odd: 1.45 + i / 10,
            result: result == null ? null : (i == 0 ? 'won' : null),
          ),
      ],
    );

StudioOptions _options(String template, StudioFormat format) => StudioOptions(
      template: template,
      format: format,
      primary: const Color(0xFF0E7C47),
      accent: const Color(0xFFF2C230),
      customText: 'Ma sélection du week-end, à vous de juger.',
      displayName: 'Kouassi Pronos',
      signature: 'Analyses par Kouassi',
      watermark: true,
      showLogos: true,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('mots interdits détectés, mots voisins acceptés', () {
    expect(forbiddenWordIn('Gain sûr ce soir'), isNotNull);
    expect(forbiddenWordIn('100% garanti'), isNotNull);
    expect(forbiddenWordIn('Pari ASSURÉ'), isNotNull);
    expect(forbiddenWordIn('Sur la route du titre'), isNull);
    expect(forbiddenWordIn('Les gagnants de la semaine'), isNull);
    expect(forbiddenWordIn('Regain de forme'), isNull);
    expect(forbiddenWordIn(null), isNull);
  });

  test('couleurs hexadécimales', () {
    expect(parseHexColor('#0E7C47'), const Color(0xFF0E7C47));
    expect(parseHexColor('0E7C47'), isNull);
    expect(parseHexColor('#XYZXYZ'), isNull);
    expect(hexOf(const Color(0xFF0E7C47)), '#0E7C47');
  });

  test('droits du studio', () {
    final r = StudioRights.fromJson({
      'enabled': true,
      'plan': 'STARTER',
      'branding': 'name',
      'watermark': true,
      'exports_per_day': 20,
      'exports_today': 22,
      'templates': [
        {
          'code': 'classique',
          'name': 'Classique',
          'min_plan': 'FREE',
          'available': true,
          'defaults': {'primary': '#111111'}
        },
        {
          'code': 'prestige',
          'name': 'Prestige',
          'min_plan': 'PRO_TIPSTER',
          'available': false
        },
      ],
    });
    expect(r.canName, isTrue);
    expect(r.canFull, isFalse);
    expect(r.remaining, 0);
    expect(r.templates.first.primary, const Color(0xFF111111));
    expect(r.templates.last.available, isFalse);
    expect(StudioRights.fromJson({'exports_per_day': null}).remaining, isNull);
  });

  test('identité : champs vides enregistrés comme absents', () {
    final j = const Branding(displayName: '  ', signature: ' Par K ').toJson();
    expect(j['display_name'], isNull);
    expect(j['signature'], 'Par K');
  });

  test('nom de fichier lisible', () {
    expect(studioFileName(_coupon(2), StudioFormat.story),
        'coupon-du-jour-31-10-story');
    expect(studioFileName(_coupon(2), StudioFormat.square),
        'coupon-du-jour-31-10-carre');
  });

  test('conversion PNG → JPG', () {
    final png =
        Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));
    final f = encodeStudioFile(png,
        format: StudioFormat.square, type: StudioFileType.jpg, baseName: 'x');
    expect(f.name, 'x.jpg');
    expect(f.mimeType, 'image/jpeg');
    expect(img.decodeJpg(f.bytes), isNotNull);
  });

  test('PDF : une page au format du visuel', () async {
    final png =
        Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));
    final f =
        await encodeStudioPdf(png, format: StudioFormat.story, baseName: 'x');
    expect(f.name, 'x.pdf');
    expect(String.fromCharCodes(f.bytes.take(5)), '%PDF-');
  });

  // Chaque modèle, chaque format, 1 à 15 sélections : rien ne déborde (Flutter signale tout débordement).
  for (final template in [
    'classique',
    'clair',
    'ticket',
    'stade',
    'prestige'
  ]) {
    for (final format in StudioFormat.values) {
      testWidgets('rendu $template ${format.code}', (tester) async {
        for (final n in [1, 5, 15]) {
          await tester.pumpWidget(Center(
            child: FittedBox(
              child: CouponVisual(
                  coupon: _coupon(n, result: n == 5 ? 'won' : null),
                  options: _options(template, format)),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '$template ${format.code} $n sélections');
          expect(find.text('Coupon Pro IA'),
              findsNothing); // nom du Tipster affiché à la place
          expect(find.text('Kouassi Pronos'), findsOneWidget);
          expect(find.text('4,25'), findsOneWidget);
          expect(find.text(studioDisclaimer), findsOneWidget);
          if (n == 15) {
            final shown = CouponVisual.maxLinesFor(format);
            expect(
                find.text('+ ${15 - shown} autres sélections'), findsOneWidget);
          }
        }
      });
    }
  }
}
