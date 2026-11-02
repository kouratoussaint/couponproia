// D5 (partie 1) : interface en anglais.
import 'dart:convert';
import 'dart:io';

import 'package:coupon_pro_ia/core/i18n/tr.dart';
import 'package:coupon_pro_ia/features/help/help_screens.dart';
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
      final bad = en.values.where(forbidden.hasMatch).toList();
      expect(bad, isEmpty);
    });

    test('aucune traduction vide', () {
      expect(en.entries.where((e) => e.value.trim().isEmpty), isEmpty);
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
