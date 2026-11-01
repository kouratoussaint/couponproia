import 'dart:convert';
import 'dart:io';

/// Réponse enregistrée pour la lecture hors connexion.
class CachedResponse {
  const CachedResponse(
      {required this.body, required this.headers, required this.savedAt});

  factory CachedResponse.decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return CachedResponse(
      body: j['b'] as String,
      headers: Map<String, String>.from(j['h'] as Map),
      savedAt: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
    );
  }

  final String body;
  final Map<String, String> headers;
  final DateTime savedAt;

  String encode() => jsonEncode({
        'b': body,
        'h': headers,
        't': savedAt.millisecondsSinceEpoch,
      });
}

/// Stockage des réponses (fichiers privés de l'application, ou mémoire dans les tests).
abstract class OfflineStore {
  Future<CachedResponse?> read(String key);
  Future<void> write(String key, CachedResponse value);
  Future<void> clear();
}

class MemoryOfflineStore implements OfflineStore {
  final values = <String, CachedResponse>{};

  @override
  Future<CachedResponse?> read(String key) async => values[key];

  @override
  Future<void> write(String key, CachedResponse value) async =>
      values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// Fichiers dans le dossier privé de l'application ; les plus anciens sont supprimés au-delà de
/// [maxFiles] fichiers ou [maxBytes] octets.
class FileOfflineStore implements OfflineStore {
  FileOfflineStore(this.dir, {this.maxFiles = 400, this.maxBytes = 20 << 20});

  final Directory dir;
  final int maxFiles;
  final int maxBytes;
  int _writes = 0;

  File _file(String key) => File('${dir.path}/$key.json');

  @override
  Future<CachedResponse?> read(String key) async {
    try {
      final f = _file(key);
      if (!await f.exists()) return null;
      return CachedResponse.decode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, CachedResponse value) async {
    try {
      await dir.create(recursive: true);
      await _file(key).writeAsString(value.encode(), flush: false);
      if (++_writes % 40 == 0) await _prune();
    } catch (_) {
      // Stockage plein ou indisponible : la lecture hors connexion est un bonus.
    }
  }

  Future<void> _prune() async {
    final files = <(File, FileStat)>[];
    await for (final e in dir.list()) {
      if (e is File) files.add((e, await e.stat()));
    }
    files.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
    var total = 0;
    for (final (i, (f, s)) in files.indexed) {
      total += s.size;
      if (i >= maxFiles || total > maxBytes) await f.delete();
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
