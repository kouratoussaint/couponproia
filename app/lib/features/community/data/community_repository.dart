import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import 'community_models.dart';

/// Message lisible pour une erreur de la communauté.
String communityErrorMessage(Object e) {
  if (e is PostgrestException) {
    switch (e.hint) {
      case 'plan_required':
        return 'Publier demande le forfait PRO TIPSTER ou BUSINESS.';
      case 'profile_required':
        return 'Crée d’abord ton profil Tipster.';
      case 'too_late':
        return 'Trop tard : un coupon se publie avant le premier coup d’envoi.';
      case 'already_published':
        return 'Ce coupon est déjà publié.';
      case 'rate_limited':
        return e.message;
      case 'feature_disabled':
        return 'La communauté est momentanément indisponible.';
    }
    if (e.code == '23505') {
      return e.message.contains('handle')
          ? 'Cet identifiant est déjà pris.'
          : 'C’est déjà fait.';
    }
    if (e.code == '22023' || e.code == '42501' || e.code == 'P0002') {
      return e.message;
    }
  }
  return 'Action impossible pour le moment. Réessaie.';
}

class CommunityRepository {
  CommunityRepository(this._client);

  final SupabaseClient _client;
  static const avatarBucket = 'tipster-avatars';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw AuthException('Session expirée');
    return id;
  }

  String? avatarUrl(String? path) => path == null
      ? null
      : _client.storage.from(avatarBucket).getPublicUrl(path);

  Future<CommunityRights> rights() async => CommunityRights.fromJson(
      Map<String, dynamic>.from(await _client.rpc('my_community') as Map));

  Future<List<Post>> feed(
      {String scope = 'all', String? tipster, DateTime? before}) async {
    final res = await _client.rpc('community_feed', params: {
      'p_scope': scope,
      'p_tipster': tipster,
      'p_before': before?.toUtc().toIso8601String(),
      'p_limit': 20,
    });
    return [
      for (final p in res as List)
        Post.fromJson(Map<String, dynamic>.from(p as Map))
    ];
  }

  Future<Post> post(int id) async => Post.fromJson(Map<String, dynamic>.from(
      await _client.rpc('post_detail', params: {'p_post': id}) as Map));

  Future<List<TipsterSummary>> directory({String? query}) async {
    final res = await _client.rpc('tipsters_directory', params: {
      'p_query': (query ?? '').trim().isEmpty ? null : query!.trim()
    });
    return [
      for (final t in res as List)
        TipsterSummary.fromJson(Map<String, dynamic>.from(t as Map))
    ];
  }

  Future<TipsterProfile?> tipster(String userId) async {
    final row = await _client
        .from('tipster_profiles')
        .select('user_id, handle, display_name, bio, avatar_path, status')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : TipsterProfile.fromJson(row);
  }

  Future<TipsterStats> stats(String userId) async =>
      TipsterStats.fromJson(Map<String, dynamic>.from(await _client
          .rpc('tipster_stats', params: {'p_tipster': userId}) as Map));

  Future<bool> isFollowing(String tipster) async {
    final row = await _client
        .from('tipster_followers')
        .select('tipster_id')
        .eq('follower_id', _uid)
        .eq('tipster_id', tipster)
        .maybeSingle();
    return row != null;
  }

  Future<void> setFollowing(String tipster, bool follow) async {
    if (follow) {
      await _client
          .from('tipster_followers')
          .insert({'follower_id': _uid, 'tipster_id': tipster});
    } else {
      await _client
          .from('tipster_followers')
          .delete()
          .eq('follower_id', _uid)
          .eq('tipster_id', tipster);
    }
  }

  Future<void> saveProfile({
    required bool create,
    required String handle,
    required String displayName,
    String? bio,
    String? avatarPath,
  }) async {
    final data = {
      'handle': handle.trim().toLowerCase(),
      'display_name': displayName.trim(),
      'bio': (bio ?? '').trim().isEmpty ? null : bio!.trim(),
      'avatar_path': avatarPath,
    };
    if (create) {
      await _client.from('tipster_profiles').insert({'user_id': _uid, ...data});
    } else {
      await _client.from('tipster_profiles').update(data).eq('user_id', _uid);
    }
  }

  Future<String> uploadAvatar(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase() == 'png' ? 'png' : 'jpg';
    final path = '$_uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(avatarBucket).uploadBinary(path, bytes,
        fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true));
    return path;
  }

  /// Supprime les anciennes photos (celle gardée exceptée).
  Future<void> cleanAvatars(String? keep) async {
    final uid = _uid;
    final files = await _client.storage.from(avatarBucket).list(path: uid);
    final unused = [
      for (final f in files)
        if ('$uid/${f.name}' != keep) '$uid/${f.name}'
    ];
    if (unused.isNotEmpty) {
      await _client.storage.from(avatarBucket).remove(unused);
    }
  }

  Future<void> setReaction(int post, bool on) async {
    if (on) {
      await _client
          .from('post_reactions')
          .insert({'post_id': post, 'user_id': _uid});
    } else {
      await _client
          .from('post_reactions')
          .delete()
          .eq('post_id', post)
          .eq('user_id', _uid);
    }
  }

  Future<void> comment(int post, String body) async {
    await _client
        .from('comments')
        .insert({'post_id': post, 'author_id': _uid, 'body': body.trim()});
  }

  Future<void> deleteComment(int id) =>
      _client.from('comments').delete().eq('id', id);

  Future<void> deletePost(int id) =>
      _client.from('posts').delete().eq('id', id);

  Future<int> createTextPost(String body) async =>
      ((await _client.rpc('create_text_post', params: {'p_body': body})) as num)
          .toInt();

  Future<int> publishCoupon(String couponId, String? comment) async =>
      ((await _client.rpc('publish_user_coupon',
              params: {'p_coupon': couponId, 'p_comment': comment})) as num)
          .toInt();

  Future<void> report(String targetType, String targetId, String reason,
      String? details) async {
    await _client.from('reports').insert({
      'reporter_id': _uid,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
    });
  }

  Future<void> block(String userId) async {
    await _client
        .from('user_blocks')
        .insert({'blocker_id': _uid, 'blocked_id': userId});
  }

  Future<void> unblock(String userId) => _client
      .from('user_blocks')
      .delete()
      .eq('blocker_id', _uid)
      .eq('blocked_id', userId);

  Future<List<BlockedUser>> blocked() async {
    final res = await _client.rpc('my_blocks');
    return [
      for (final b in res as List)
        BlockedUser.fromJson(Map<String, dynamic>.from(b as Map))
    ];
  }

  Future<List<ModerationItem>> moderationQueue() async {
    final res = await _client.rpc('moderation_queue');
    return [
      for (final m in res as List)
        ModerationItem.fromJson(Map<String, dynamic>.from(m as Map))
    ];
  }

  Future<void> moderate(String targetType, String targetId, String action,
      {String? note, int? report}) async {
    await _client.rpc('moderate', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_action': action,
      'p_note': note,
      'p_report': report,
    });
  }

  // --- Équipes suivies ------------------------------------------------------------------------
  Future<Map<int, String>> favoriteTeams() async {
    final rows = await _client
        .from('user_favorites')
        .select('team_id, team:teams(name)')
        .eq('user_id', _uid)
        .order('created_at');
    return {
      for (final r in rows)
        (r['team_id'] as num).toInt():
            (r['team'] as Map?)?['name'] as String? ?? 'Équipe',
    };
  }

  Future<void> setFavoriteTeam(int teamId, bool on) async {
    if (on) {
      await _client
          .from('user_favorites')
          .insert({'user_id': _uid, 'team_id': teamId});
    } else {
      await _client
          .from('user_favorites')
          .delete()
          .eq('user_id', _uid)
          .eq('team_id', teamId);
    }
  }
}

final communityRepositoryProvider = Provider<CommunityRepository>(
    (ref) => CommunityRepository(ref.watch(supabaseClientProvider)));

final communityRightsProvider = FutureProvider.autoDispose<CommunityRights>(
    (ref) => ref.watch(communityRepositoryProvider).rights());

final feedProvider = FutureProvider.autoDispose.family<List<Post>, String>(
    (ref, scope) => ref.watch(communityRepositoryProvider).feed(scope: scope));

final tipsterFeedProvider = FutureProvider.autoDispose
    .family<List<Post>, String>((ref, tipster) => ref
        .watch(communityRepositoryProvider)
        .feed(scope: 'tipster', tipster: tipster));

final postProvider = FutureProvider.autoDispose.family<Post, int>(
    (ref, id) => ref.watch(communityRepositoryProvider).post(id));

final directoryProvider = FutureProvider.autoDispose
    .family<List<TipsterSummary>, String>((ref, query) =>
        ref.watch(communityRepositoryProvider).directory(query: query));

final tipsterProvider = FutureProvider.autoDispose
    .family<TipsterProfile?, String>(
        (ref, id) => ref.watch(communityRepositoryProvider).tipster(id));

final tipsterStatsProvider = FutureProvider.autoDispose
    .family<TipsterStats, String>(
        (ref, id) => ref.watch(communityRepositoryProvider).stats(id));

final isFollowingProvider = FutureProvider.autoDispose.family<bool, String>(
    (ref, id) => ref.watch(communityRepositoryProvider).isFollowing(id));

final moderationQueueProvider =
    FutureProvider.autoDispose<List<ModerationItem>>(
        (ref) => ref.watch(communityRepositoryProvider).moderationQueue());

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>(
    (ref) => ref.watch(communityRepositoryProvider).blocked());

final favoriteTeamsProvider = FutureProvider<Map<int, String>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(communityRepositoryProvider).favoriteTeams();
});
