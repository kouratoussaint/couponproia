import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Valeurs publiques du projet Firebase, fournies à la compilation (google-services.json).
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.senderId,
    required this.projectId,
  });

  static const fromEnvironment = FirebaseConfig(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    senderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );

  final String apiKey;
  final String appId;
  final String senderId;
  final String projectId;

  bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty &&
      projectId.isNotEmpty;

  FirebaseOptions get options => FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId);
}

/// Notifications sur le téléphone (Firebase Cloud Messaging). Sans configuration Firebase,
/// rien n'est fait : la boîte de réception de l'app reste disponible.
class PushService {
  PushService(this._ref,
      {FirebaseConfig config = FirebaseConfig.fromEnvironment})
      : _config = config;

  final Ref _ref;
  final FirebaseConfig _config;
  bool _started = false;
  bool _denied = false;
  String? _token;
  final _subs = <StreamSubscription<Object?>>[];

  bool get available =>
      _config.isConfigured &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  /// Vrai si l'utilisateur a refusé les notifications dans les réglages du téléphone.
  bool get permissionDenied => _denied;

  /// Appelé après la connexion. [onOpen] reçoit la route à ouvrir (notification touchée),
  /// [onForeground] le titre d'une notification reçue app ouverte.
  Future<void> start({
    required void Function(String route) onOpen,
    required void Function(String title, String? route) onForeground,
    String? appVersion,
  }) async {
    if (_started || !available) return;
    _started = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _config.options);
      }
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission();
      _denied = perm.authorizationStatus == AuthorizationStatus.denied;
      if (_denied) return;
      final repo = _ref.read(notificationsRepositoryProvider);
      // Jeton FCM classique, éprouvé avec l'envoi HTTP v1 du serveur (champ « token »).
      // Firebase propose désormais register()/onRegistered (identifiant d'installation, champ
      // « fid ») : migration prévue quand l'envoi par « fid » sera vérifié de bout en bout.
      // ignore: deprecated_member_use
      _token = await messaging.getToken();
      if (_token != null) {
        await repo.registerDevice(_token!, version: appVersion);
      }
      // ignore: deprecated_member_use
      _subs.add(messaging.onTokenRefresh.listen((t) async {
        _token = t;
        await repo.registerDevice(t, version: appVersion);
      }));
      _subs.add(FirebaseMessaging.onMessage.listen((m) {
        _ref.invalidate(unreadCountProvider);
        final title = m.notification?.title;
        if (title != null) onForeground(title, routeOf(m.data));
      }));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final route = routeOf(m.data);
        if (route != null) onOpen(route);
      }));
      final initial = await messaging.getInitialMessage();
      final route = initial == null ? null : routeOf(initial.data);
      if (route != null) onOpen(route);
    } catch (e) {
      debugPrint(trf('Notifications indisponibles : {0}', [e]));
    }
  }

  /// À la déconnexion : cet appareil ne reçoit plus les notifications du compte.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final token = _token;
    _token = null;
    _started = false;
    if (token != null) {
      try {
        await _ref
            .read(notificationsRepositoryProvider)
            .unregisterDevice(token);
      } catch (_) {}
    }
  }
}

/// Route interne transmise par le serveur (uniquement des chemins de l'app).
String? routeOf(Map<String, dynamic> data) {
  final r = data['route'];
  if (r is! String || r.isEmpty || !r.startsWith('/') || r.startsWith('//')) {
    return null;
  }
  return r;
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
