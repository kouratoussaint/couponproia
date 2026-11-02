import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Un rapport en attente d'envoi.
class ErrorReport {
  const ErrorReport(
      {required this.kind, required this.message, this.stack, this.context});

  final String kind;
  final String message;
  final String? stack;
  final String? context;

  String get signature =>
      '$kind|${message.split('\n').first}|${(stack ?? '').split('\n').take(3).join('|')}';
}

/// Plantages et lenteurs : remontés au serveur (regroupés par empreinte, sans contenu personnel)
/// quand l'utilisateur est connecté et ne s'y est pas opposé (Profil → Rapports d'erreurs).
class ErrorReporter {
  ErrorReporter(this._prefs, {Future<void> Function(ErrorReport r)? send})
      : _sendOverride = send;

  static const prefKey = 'error_reports_enabled';
  static const _maxQueue = 20;

  final SharedPreferences _prefs;
  final Future<void> Function(ErrorReport r)? _sendOverride;
  final _seen = <String>{};
  final queue = <ErrorReport>[];
  Timer? _timer;

  /// Écran courant (chemin de la page), mis à jour par le routeur.
  static String? currentRoute;
  String version = '';
  int? build;

  bool get enabled => _prefs.getBool(prefKey) ?? true;
  Future<void> setEnabled(bool v) async {
    await _prefs.setBool(prefKey, v);
    if (!v) queue.clear();
  }

  static String _os() {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'inconnu';
    }
  }

  /// Erreurs de réseau : attendues hors connexion, pas des plantages.
  static bool ignorable(Object error) {
    final s = error.runtimeType.toString();
    return s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('TimeoutException') ||
        s.contains('HandshakeException') ||
        s.contains('AuthRetryableFetchException');
  }

  void record(String kind, Object error, StackTrace? stack, {String? context}) {
    if (!enabled || ignorable(error)) return;
    final message = error.toString();
    _enqueue(ErrorReport(
      kind: kind,
      message: message.length > 500 ? message.substring(0, 500) : message,
      stack: stack?.toString(),
      context: context ?? currentRoute,
    ));
  }

  void recordSlow(String path, Duration d) {
    if (!enabled) return;
    _enqueue(ErrorReport(
        kind: 'slow',
        message: trf('Requête lente : {0} s',
            [(d.inMilliseconds / 1000).toStringAsFixed(1)]),
        context: path));
  }

  void _enqueue(ErrorReport r) {
    // Une fois par session et par empreinte (une boucle d'erreurs n'inonde pas le serveur).
    final sig = r.kind == 'slow' ? 'slow|${r.context}' : r.signature;
    if (!_seen.add(sig) || queue.length >= _maxQueue) return;
    queue.add(r);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), flush);
  }

  Future<void> _send(ErrorReport r) async {
    if (_sendOverride != null) return _sendOverride(r);
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) throw StateError(tr('non connecté'));
    await client.rpc('report_client_error', params: {
      'p_kind': r.kind,
      'p_message': r.message,
      'p_stack': r.stack == null || r.stack!.length <= 4000
          ? r.stack
          : r.stack!.substring(0, 4000),
      'p_context': r.context,
      'p_version': version,
      'p_build': build,
      'p_os': _os(),
    });
  }

  /// Envoie ce qui attend ; ce qui échoue (hors connexion, déconnecté) est gardé pour plus tard.
  Future<void> flush() async {
    if (!enabled) return;
    for (final r in [...queue]) {
      try {
        await _send(r);
        queue.remove(r);
      } catch (_) {
        return;
      }
    }
  }
}

/// Surchargé dans `main()`.
final errorReporterProvider = Provider<ErrorReporter>(
  (ref) => throw UnimplementedError('errorReporterProvider non initialisé'),
);
