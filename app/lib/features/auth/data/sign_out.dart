import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/data/push_service.dart';
import 'auth_repository.dart';

/// Déconnexion : arrêt des notifications de l'appareil, puis fin de session.
///
/// Les services sont lus tout de suite : l'écran appelant (menu latéral, Profil)
/// peut disparaître pendant l'attente, et son `ref` n'est alors plus utilisable
/// (erreur « Cannot use ref after the widget was disposed », corrigée au lot 27).
Future<void> signOutEverywhere(WidgetRef ref) async {
  final push = ref.read(pushServiceProvider);
  final auth = ref.read(authRepositoryProvider);
  await push.stop();
  await auth.signOut();
}
