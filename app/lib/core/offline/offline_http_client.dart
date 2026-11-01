import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'offline_store.dart';

/// Hors connexion : date des données affichées (null = en ligne).
final offlineSince = ValueNotifier<DateTime?>(null);

/// Fonctions de lecture (RPC) dont la réponse peut être relue hors connexion.
const offlineRpcs = {
  'platform_performance',
  'my_performance',
  'match_insights',
  'featured_match_today',
  'coupon_analyses',
  'my_entitlements',
  'my_credits',
  'my_permissions',
  'my_legal_status',
  'tipsters_directory',
  'tipster_stats',
  'community_feed',
  'post_detail',
};

/// Client HTTP de Supabase : enregistre les lectures réussies (tables et fonctions de lecture) et
/// les resservit quand le réseau manque. Chaque réponse est rangée par compte (jamais partagée entre
/// deux utilisateurs du même téléphone). Signale aussi les requêtes lentes.
class OfflineHttpClient extends http.BaseClient {
  OfflineHttpClient(this._inner, this._store,
      {this.timeout = const Duration(seconds: 20),
      this.slowThreshold = const Duration(seconds: 8),
      this.onSlow});

  final http.Client _inner;
  final OfflineStore _store;
  final Duration timeout;
  final Duration slowThreshold;

  /// Requête lente : chemin sans paramètres (aucune donnée personnelle) et durée.
  final void Function(String path, Duration duration)? onSlow;

  static const _maxBody = 1500000;

  /// Clé d'une requête : compte, méthode, adresse complète et corps (fonctions).
  static String keyOf(http.BaseRequest r) {
    final body = r is http.Request ? r.body : '';
    final raw = '${userOf(r.headers)}|${r.method}|${r.url}|$body';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  /// Identifiant du compte lu dans le jeton (« anon » sans session).
  static String userOf(Map<String, String> headers) {
    final auth = headers['Authorization'] ?? headers['authorization'] ?? '';
    final parts = auth.replaceFirst('Bearer ', '').split('.');
    if (parts.length != 3) return 'anon';
    try {
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      return payload['sub'] as String? ?? 'anon';
    } catch (_) {
      return 'anon';
    }
  }

  static bool cacheable(http.BaseRequest r) {
    final path = r.url.path;
    if (!path.contains('/rest/v1/')) return false;
    if (r.method == 'GET') return true;
    if (r.method != 'POST' || r is! http.Request) return false;
    final m = RegExp(r'/rest/v1/rpc/([a-z0-9_]+)$').firstMatch(path);
    return m != null && offlineRpcs.contains(m.group(1));
  }

  static String _label(Uri url) {
    final i = url.path.indexOf('/rest/v1/');
    return i < 0 ? url.path : url.path.substring(i + 8);
  }

  static bool _isNetworkError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is http.ClientException ||
      e is OSError;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rest = request.url.path.contains('/rest/v1/');
    final watch = Stopwatch()..start();
    if (!cacheable(request)) {
      final res = await _inner.send(request);
      if (rest) _checkSlow(request.url, watch.elapsed);
      return res;
    }
    final key = keyOf(request);
    try {
      final res = await _inner.send(request).timeout(timeout);
      final bytes = await res.stream.toBytes();
      _checkSlow(request.url, watch.elapsed);
      offlineSince.value = null;
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          bytes.length <= _maxBody) {
        unawaited(_store.write(
            key,
            CachedResponse(
              body: utf8.decode(bytes, allowMalformed: true),
              headers: {
                for (final h in ['content-type', 'content-range'])
                  if (res.headers[h] != null) h: res.headers[h]!,
              },
              savedAt: DateTime.now(),
            )));
      }
      return http.StreamedResponse(Stream.value(bytes), res.statusCode,
          headers: res.headers,
          request: request,
          reasonPhrase: res.reasonPhrase,
          contentLength: bytes.length);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      final cached = await _store.read(key);
      if (cached == null) rethrow;
      final prev = offlineSince.value;
      if (prev == null || cached.savedAt.isBefore(prev)) {
        offlineSince.value = cached.savedAt;
      }
      final bytes = utf8.encode(cached.body);
      return http.StreamedResponse(Stream.value(bytes), 200,
          headers: {...cached.headers, 'x-offline-cache': '1'},
          request: request,
          contentLength: bytes.length);
    }
  }

  void _checkSlow(Uri url, Duration d) {
    if (d >= slowThreshold) onSlow?.call(_label(url), d);
  }

  @override
  void close() => _inner.close();
}
