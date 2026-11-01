import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Lien public de partage : ouvre l'écran dans l'application (Android), ou propose de l'installer.
String shareLinkFor(String supabaseUrl, {String? couponId, int? matchId}) {
  final base = supabaseUrl.endsWith('/')
      ? supabaseUrl.substring(0, supabaseUrl.length - 1)
      : supabaseUrl;
  final path = couponId != null ? 'c/$couponId' : 'm/$matchId';
  return '$base/functions/v1/share/$path';
}

/// Même chose depuis un widget (null si l'app n'est pas configurée).
String? shareLink(WidgetRef ref, {String? couponId, int? matchId}) {
  final config = ref.read(appConfigProvider);
  if (!config.isConfigured) return null;
  return shareLinkFor(config.supabaseUrl, couponId: couponId, matchId: matchId);
}
