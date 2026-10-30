import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'studio_models.dart';

class StudioException implements Exception {
  const StudioException(this.message);

  final String message;

  @override
  String toString() => message;
}

String studioErrorMessage(Object e) {
  if (e is StudioException) return e.message;
  if (e is PostgrestException) {
    switch (e.hint) {
      case 'quota_exceeded':
        return '${e.message}. Les forfaits supérieurs en permettent davantage.';
      case 'template_locked':
        return 'Ce modèle demande un forfait supérieur.';
      case 'coupon_unavailable':
        return 'Ce coupon n’est pas disponible pour un visuel (réservé ou introuvable).';
      case 'feature_disabled':
        return 'Le studio est momentanément indisponible.';
    }
    if (e.code == '22023' || e.code == '42501') return e.message;
  }
  return 'Action impossible pour le moment. Réessayez.';
}

class StudioRepository {
  StudioRepository(this._client);

  final SupabaseClient _client;
  static const _bucket = 'branding';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const StudioException('Connexion requise.');
    return id;
  }

  Future<StudioRights> rights() async => StudioRights.fromJson(
      Map<String, dynamic>.from(await _client.rpc('my_studio') as Map));

  Future<Branding> branding() async {
    final row = await _client
        .from('user_branding')
        .select()
        .eq('user_id', _uid)
        .maybeSingle();
    return row == null ? const Branding() : Branding.fromJson(row);
  }

  Future<void> saveBranding(Branding b) async {
    await _client
        .from('user_branding')
        .upsert({'user_id': _uid, ...b.toJson()});
  }

  /// Envoie un logo ou une couverture dans le dossier privé de l'utilisateur ; renvoie son chemin.
  Future<String> uploadImage(
      String kind, Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path = '$_uid/$kind-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true),
        );
    return path;
  }

  /// Supprime les images du dossier de l'utilisateur qui ne sont plus utilisées
  /// (remplacées, retirées, ou choisies sans être enregistrées).
  Future<void> removeUnusedImages(Set<String?> keep) async {
    final uid = _uid;
    final files = await _client.storage.from(_bucket).list(path: uid);
    final unused = [
      for (final f in files)
        if (!keep.contains('$uid/${f.name}')) '$uid/${f.name}'
    ];
    if (unused.isNotEmpty) await _client.storage.from(_bucket).remove(unused);
  }

  Future<Uint8List?> downloadImage(String? path) async {
    if (path == null) return null;
    try {
      return await _client.storage.from(_bucket).download(path);
    } catch (_) {
      return null;
    }
  }

  /// Le serveur vérifie le modèle, le coupon et le quota, puis journalise l'export.
  Future<void> authorizeExport({
    required StudioCoupon coupon,
    required String template,
    required StudioFormat format,
    required StudioFileType fileType,
  }) async {
    await _client.rpc('studio_export', params: {
      'p_source_kind': coupon.sourceKind,
      'p_source_id': coupon.sourceId,
      'p_template': template,
      'p_format': format.code,
      'p_file_type': fileType.name,
    });
  }
}

final studioRepositoryProvider = Provider<StudioRepository>(
    (ref) => StudioRepository(ref.watch(supabaseClientProvider)));

final studioRightsProvider = FutureProvider.autoDispose<StudioRights>(
    (ref) => ref.watch(studioRepositoryProvider).rights());

final brandingProvider = FutureProvider.autoDispose<Branding>(
    (ref) => ref.watch(studioRepositoryProvider).branding());

/// Images de l'identité visuelle (téléchargées une fois).
final brandingImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, String?>(
        (ref, path) => ref.watch(studioRepositoryProvider).downloadImage(path));
