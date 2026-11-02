// Traduction de l'interface (D5). Le français est la langue source : chaque texte affiché passe
// par tr('texte français') ou trf('texte avec {0}', [valeur]). En anglais, le texte est cherché
// dans assets/i18n/en.json (clé = texte français) ; s'il manque, le français s'affiche.
// La langue est fixée au démarrage (changer de langue redémarre l'application).
import 'dart:convert';

import 'package:flutter/services.dart';

/// Langues proposées.
const appLanguages = {'fr': 'Français', 'en': 'English'};

/// Clé de la langue choisie (préférences du téléphone).
const languagePrefKey = 'app.language';

/// Langue au premier lancement : l'anglais si le téléphone est en anglais, sinon le français.
String defaultLanguage(String deviceLanguageCode) =>
    deviceLanguageCode == 'en' ? 'en' : 'fr';

String _lang = 'fr';
Map<String, String> _en = const {};

/// Langue de l'interface (« fr » ou « en »).
String get appLanguage => _lang;

/// Charge la langue choisie (appelé avant runApp).
Future<void> loadLanguage(String lang) async {
  _lang = appLanguages.containsKey(lang) ? lang : 'fr';
  if (_lang == 'en') {
    try {
      final raw = await rootBundle.loadString('assets/i18n/en.json');
      _en = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _en = const {};
    }
  } else {
    _en = const {};
  }
}

/// Pour les tests : langue et traductions fournies directement.
void setLanguageForTest(String lang, Map<String, String> en) {
  _lang = lang;
  _en = en;
}

/// Texte traduit (le français si aucune traduction).
String tr(String fr) => _lang == 'fr' ? fr : (_en[fr] ?? fr);

/// Texte avec valeurs : {0}, {1}… sont remplacés dans l'ordre.
String trf(String fr, List<Object?> args) {
  var t = tr(fr);
  for (var i = 0; i < args.length; i++) {
    t = t.replaceAll('{$i}', '${args[i]}');
  }
  return t;
}

/// Séparateur décimal affiché : « 1,95 » en français, « 1.95 » en anglais.
String get decimalSeparator => _lang == 'en' ? '.' : ',';

/// Séparateur de milliers : « 12 500 » en français, « 12,500 » en anglais.
String get thousandsSeparator => _lang == 'en' ? ',' : '\u202f';

/// Pourcentage : « 53 % » en français, « 53% » en anglais.
String percentLabel(int n) => _lang == 'en' ? '$n%' : '$n %';

final _selectionCount = RegExp(r'^(\d+) sélections?$');

/// Titre de coupon venu du serveur (« Prudent · 02/11 », « Coupon manuel · 3 sélections ») :
/// chaque partie connue est traduite, le reste (nom choisi, date) est gardé tel quel.
String trTitle(String title) {
  if (_lang == 'fr') return title;
  return title.split(' · ').map((part) {
    final m = _selectionCount.firstMatch(part);
    if (m != null) {
      final n = int.parse(m[1]!);
      return '$n selection${n > 1 ? 's' : ''}';
    }
    return tr(part.replaceAll("'", '’'));
  }).join(' · ');
}
