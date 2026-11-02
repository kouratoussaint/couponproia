import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/i18n/tr.dart';

/// Langue du compte alignée sur celle de l'app (D5) : le serveur écrit notifications, e-mails
/// et analyses dans la langue du profil, et les e-mails de connexion dans celle des métadonnées.
/// Une seule fois par session et par langue ; hors ligne, réessayé à la connexion suivante.
Future<void> syncAccountLanguage(SupabaseClient client, {String? lang}) async {
  final user = client.auth.currentUser;
  if (user == null) return;
  final wanted = lang ?? appLanguage;
  if (user.userMetadata?['locale'] == wanted) return;
  try {
    await client.from('profiles').update({'locale': wanted}).eq('id', user.id);
    await client.auth.updateUser(UserAttributes(data: {'locale': wanted}));
  } catch (_) {
    // Sans réseau : la prochaine ouverture recommencera.
  }
}
