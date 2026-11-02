import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Codes des documents légaux, dans l'ordre d'affichage.
const legalCodes = ['terms', 'privacy', 'community'];

final legalTitles = {
  'terms': tr('Conditions générales d’utilisation'),
  'privacy': tr('Politique de confidentialité'),
  'community': tr('Règles de la communauté'),
};

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.code,
    required this.version,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.translated = false,
    this.english,
    String? frTitle,
    String? frBody,
  })  : frTitle = frTitle ?? title,
        frBody = frBody ?? body;

  /// En anglais, la traduction (si elle existe) remplace le titre et le texte affichés ;
  /// la version française reste celle qui fait foi et qui est acceptée.
  factory LegalDocument.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? en;
    for (final t in (j['legal_translations'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(t as Map);
      if (m['language'] == 'en') en = m;
    }
    final useEn = appLanguage == 'en' && en != null;
    return LegalDocument(
      id: (j['id'] as num).toInt(),
      code: j['code'] as String,
      version: j['version'] as String,
      title: useEn ? en['title'] as String : j['title'] as String,
      body: useEn ? en['body'] as String? ?? '' : j['body'] as String? ?? '',
      publishedAt: DateTime.parse(j['published_at'] as String).toLocal(),
      translated: useEn,
      frTitle: j['title'] as String,
      frBody: j['body'] as String? ?? '',
      english: en == null
          ? null
          : (title: en['title'] as String, body: en['body'] as String? ?? ''),
    );
  }

  final int id;
  final String code;
  final String version;
  final String title;
  final String body;
  final DateTime publishedAt;

  /// Texte affiché : la traduction anglaise.
  final bool translated;

  /// Traduction anglaise enregistrée (console).
  final ({String title, String body})? english;

  /// Version française (celle qui fait foi), quelle que soit la langue de l'app.
  final String frTitle;
  final String frBody;
}

/// Version d'un document à accepter.
class PendingDocument {
  const PendingDocument(
      {required this.id,
      required this.code,
      required this.version,
      required this.title});

  factory PendingDocument.fromJson(Map<String, dynamic> j) => PendingDocument(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String,
        version: j['version'] as String,
        title: j['title'] as String,
      );

  final int id;
  final String code;
  final String version;
  final String title;
}

class LegalRepository {
  LegalRepository(this._client);

  final SupabaseClient _client;

  /// Dernière version publiée d'un document (lisible sans connexion).
  Future<LegalDocument?> current(String code) async {
    final row = await _client
        .from('legal_documents')
        .select(
            'id, code, version, title, body, published_at, legal_translations(language, title, body)')
        .eq('code', code)
        .order('published_at', ascending: false)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : LegalDocument.fromJson(row);
  }

  Future<List<PendingDocument>> pending() async {
    final r =
        Map<String, dynamic>.from(await _client.rpc('my_legal_status') as Map);
    return [
      for (final p in (r['pending'] as List? ?? const []))
        PendingDocument.fromJson(Map<String, dynamic>.from(p as Map)),
    ];
  }

  Future<void> accept(List<int> ids) =>
      _client.rpc('accept_legal', params: {'p_document_ids': ids});

  Future<void> publish(
          {required String code,
          required String version,
          required String title,
          required String body}) =>
      _client.rpc('admin_publish_legal', params: {
        'p_code': code,
        'p_version': version,
        'p_title': title,
        'p_body': body,
      });
}

extension LegalTranslation on LegalRepository {
  /// Traduction anglaise d'une version (console, réglages).
  Future<void> saveEnglish(
          {required int documentId,
          required String title,
          required String body}) =>
      _client.rpc('admin_save_legal_translation', params: {
        'p_document_id': documentId,
        'p_title': title,
        'p_body': body,
      });
}

final legalRepositoryProvider = Provider<LegalRepository>(
    (ref) => LegalRepository(ref.watch(supabaseClientProvider)));

final legalDocumentProvider = FutureProvider.autoDispose
    .family<LegalDocument?, String>(
        (ref, code) => ref.watch(legalRepositoryProvider).current(code));

/// Documents à accepter par l'utilisateur connecté (vide si tout est accepté).
final legalStatusProvider = FutureProvider<List<PendingDocument>>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  if (uid == null) return const <PendingDocument>[];
  return ref.watch(legalRepositoryProvider).pending();
});

/// Remplace les champs de l'éditeur ({{editeur}}…) par le réglage public `legal.editor`.
/// Un champ non renseigné disparaît ; l'éditeur et le contact ont une valeur par défaut.
String fillLegalPlaceholders(String body, Map<String, dynamic> settings) {
  final editor = settings['legal.editor'] is Map
      ? Map<String, dynamic>.from(settings['legal.editor'] as Map)
      : const <String, dynamic>{};
  String field(String key) => (editor[key] as String? ?? '').trim();
  final email = (settings['app.support_email'] as String? ?? '').trim();
  final values = {
    'editeur': field('name').isEmpty
        ? tr('l’éditeur de Coupon Pro IA')
        : field('name'),
    'forme': field('legal_form'),
    'adresse': field('address'),
    'pays': field('country'),
    'immatriculation': field('registration'),
    'contact': email.isEmpty
        ? tr('le support (Profil → Contacter le support)')
        : email,
  };
  var out = body;
  values.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
  // Nettoyage des séparateurs laissés par les champs vides (« , , », espaces doubles).
  return out
      .replaceAll(RegExp(r'(,\s*)+(?=[.,])'), '')
      .replaceAll(RegExp(r',(\s*,)+'), ',')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAllMapped(RegExp(r' +([,.])'), (m) => m[1]!);
}
