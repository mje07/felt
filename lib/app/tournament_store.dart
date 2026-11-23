import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:poker_engine/poker_engine.dart';

/// Finished Sit & Gos as JSON lines in the app-support directory.
class TournamentStore {
  TournamentStore._(this._file);

  final File? _file;
  final List<TournamentResult> results = [];

  static TournamentStore current = TournamentStore._(null);

  static Future<TournamentStore> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}tournaments.jsonl');
      final store = TournamentStore._(file);
      if (await file.exists()) {
        for (final l in await file.readAsLines()) {
          try {
            store.results.add(TournamentResult.fromJson((jsonDecode(l) as Map).cast<String, Object?>()));
          } catch (_) {}
        }
      }
      return current = store;
    } catch (_) {
      return current = TournamentStore._(null);
    }
  }

  factory TournamentStore.memory() => TournamentStore._(null);

  Future<void> add(TournamentResult r) async {
    results.add(r);
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString('${jsonEncode(r.toJson())}\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> clear() async {
    results.clear();
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
