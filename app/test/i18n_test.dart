// D5 (partie 1) : interface en anglais.
import 'dart:convert';
import 'dart:io';

import 'package:coupon_pro_ia/core/i18n/tr.dart';
import 'package:coupon_pro_ia/features/coupons/data/coupon_models.dart';
import 'package:coupon_pro_ia/features/help/help_screens.dart';
import 'package:coupon_pro_ia/features/legal/legal_repository.dart';
import 'package:coupon_pro_ia/features/simulator/data/stake_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _loadEn() => Map<String, String>.from(
    jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map);

/// Textes passés à tr()/trf() dans lib (littéraux simples).
Set<String> _wrappedLiterals() {
  final pattern =
      RegExp(r"""\btrf?\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""");
  final found = <String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (f.path.endsWith('tr.dart')) continue;
    for (final m in pattern.allMatches(f.readAsStringSync())) {
      final raw = m.group(1) ?? m.group(2)!;
      found.add(raw
          .replaceAll(r"\'", "'")
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\$', r'$')
          .replaceAll(r'\\', r'\'));
    }
  }
  return found;
}

void main() {
  tearDown(() => setLanguageForTest('fr', const {}));

  group('tr / trf', () {
    test('français : texte source inchangé', () {
      setLanguageForTest('fr', const {'Bonjour': 'Hello'});
      expect(tr('Bonjour'), 'Bonjour');
      expect(trf('{0} coupon{1}', [2, 's']), '2 coupons');
    });

    test('anglais : traduction, sinon repli sur le français', () {
      setLanguageForTest('en', const {
        'Bonjour': 'Hello',
        '{0} coupon{1} décidé{2}': '{0} coupon{1} decided',
      });
      expect(tr('Bonjour'), 'Hello');
      expect(tr('Texte absent'), 'Texte absent');
      expect(
          trf('{0} coupon{1} décidé{2}', [3, 's', 's']), '3 coupons decided');
    });

    test('titres de coupons venus du serveur', () {
      setLanguageForTest('fr', const {});
      expect(trTitle('Prudent · 02/11'), 'Prudent · 02/11');
      setLanguageForTest('en', const {
        'Prudent': 'Cautious',
        'Coupon de l’assistant': 'Assistant coupon',
      });
      expect(trTitle('Prudent · 02/11'), 'Cautious · 02/11');
      expect(trTitle('Prudent · lundi 2 novembre'),
          'Cautious · Monday 2 November');
      expect(trTitle("Coupon de l'assistant · 3 sélections"),
          'Assistant coupon · 3 selections');
      expect(trTitle('Mon combiné du soir · 1 sélection'),
          'Mon combiné du soir · 1 selection');
    });

    test('langue par défaut selon le téléphone', () {
      expect(defaultLanguage('en'), 'en');
      expect(defaultLanguage('fr'), 'fr');
      expect(defaultLanguage('wo'), 'fr');
    });

    test('nombres : séparateurs et pourcentages selon la langue', () {
      setLanguageForTest('fr', const {});
      expect(decimalSeparator, ',');
      expect(percentLabel(62), '62 %');
      expect(money(12500), '12 500 FCFA');
      setLanguageForTest('en', const {});
      expect(decimalSeparator, '.');
      expect(percentLabel(62), '62%');
      expect(money(12500), '12,500 FCFA');
    });
  });

  group('catalogue anglais', () {
    final en = _loadEn();

    test('chaque texte de l’interface a sa traduction', () {
      final missing =
          _wrappedLiterals().where((t) => !en.containsKey(t)).toList()..sort();
      expect(missing, isEmpty,
          reason: 'Ajoutez ces textes à assets/i18n/en.json '
              '(scripts/i18n/check_en.py les liste aussi).');
    });

    test('les valeurs {n} de l’anglais existent dans le français', () {
      final ph = RegExp(r'\{\d+\}');
      final bad = <String>[];
      en.forEach((fr, english) {
        final source = ph.allMatches(fr).map((m) => m[0]).toSet();
        for (final m in ph.allMatches(english)) {
          if (!source.contains(m[0])) bad.add(fr);
        }
      });
      expect(bad, isEmpty);
    });

    test('aucun mot interdit dans les traductions', () {
      final forbidden = RegExp(r'\b(guaranteed?|sure bet|winnings|risk-free)\b',
          caseSensitive: false);
      // Les mots cités entre guillemets (règles, messages de refus) ne sont pas des promesses.
      final quoted = RegExp(r'“[^”]*”|«[^»]*»');
      final bad = en.values
          .where((v) => forbidden.hasMatch(v.replaceAll(quoted, '')))
          .toList();
      expect(bad, isEmpty);
    });

    test('aucune traduction vide', () {
      expect(en.entries.where((e) => e.value.trim().isEmpty), isEmpty);
    });
  });

  group('textes du serveur selon la langue (partie 2)', () {
    final now = DateTime.utc(2026, 11, 2, 12).toIso8601String();
    Map<String, dynamic> couponJson() => {
          'id': 'c1',
          'category': 'prudent',
          'title': 'Prudent · lundi 2 novembre',
          'risk_level': 'prudent',
          'total_odd': 2.5,
          'combined_probability': 0.4,
          'status': 'published',
          'publish_at': now,
          'first_kickoff_at': now,
          'last_kickoff_at': now,
          'engine_version': 'v',
          'created_at': now,
          'analysis': {
            'analyse_generale': 'Résumé',
            'points_de_vigilance': ['Point'],
            'source': 'ia',
            'en': {
              'analyse_generale': 'Summary',
              'points_de_vigilance': ['Point EN'],
              'market_note': 'Market note'
            },
          },
          'coupon_selections': [
            {
              'position': 1,
              'selection_key': '1X2.HOME',
              'odd': 1.5,
              'odds_captured_at': now,
              'model_probability': 0.6,
              'reliability': 'bonne',
              'justification': 'Modèle : 60 %',
              'justification_en': 'Model: 60%',
              'match': {
                'id': 7,
                'kickoff_at': now,
                'status': 'scheduled',
                'home': {'name': 'Lille'},
                'away': {'name': 'Lens'},
              },
            }
          ],
        };

    test('coupon de la plateforme : résumé et justification en anglais', () {
      setLanguageForTest('en', const {});
      final c = Coupon.fromJson(couponJson());
      expect(c.summary, 'Summary');
      expect(c.vigilance, ['Point EN']);
      expect(c.summaryFromAi, isTrue);
      expect(c.selections.single.justification, 'Model: 60%');
      setLanguageForTest('fr', const {});
      final f = Coupon.fromJson(couponJson());
      expect(f.summary, 'Résumé');
      expect(f.selections.single.justification, 'Modèle : 60 %');
    });

    test('document légal : traduction affichée, version française gardée', () {
      final j = {
        'id': 1,
        'code': 'terms',
        'version': '2026-10-31',
        'title': 'Conditions générales d’utilisation',
        'body': 'Texte français',
        'published_at': now,
        'legal_translations': [
          {'language': 'en', 'title': 'General terms of use', 'body': 'English'}
        ],
      };
      setLanguageForTest('en', const {});
      final d = LegalDocument.fromJson(j);
      expect((d.title, d.body, d.translated),
          ('General terms of use', 'English', true));
      expect(d.frBody, 'Texte français');
      setLanguageForTest('fr', const {});
      final f = LegalDocument.fromJson(j);
      expect((f.title, f.translated),
          ('Conditions générales d’utilisation', false));
      expect(f.english?.title, 'General terms of use');
    });

    test('lettres de forme en anglais', () {
      setLanguageForTest('en', const {});
      expect([
        for (final l in ['V', 'N', 'D']) formLetterShown(l)
      ], [
        'W',
        'D',
        'L'
      ]);
      setLanguageForTest('fr', const {});
      expect(formLetterShown('V'), 'V');
    });
  });

  testWidgets('l’aide s’affiche en anglais', (tester) async {
    setLanguageForTest('en', _loadEn());
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: HelpScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Aide et questions fréquentes'), findsNothing);
    expect(find.text('Help and FAQ'), findsOneWidget);
  });
}
