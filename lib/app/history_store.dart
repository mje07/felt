import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:poker_engine/poker_engine.dart';

/// Hand histories as JSON lines in the app-support directory.
class HistoryStore {
  HistoryStore._(this._file);

  /// Hands kept (oldest dropped first); room for imported histories.
  static const _keep = 10000;
  final File? _file;
  final List<HandHistory> hands = [];

  static Future<HistoryStore> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}hand_history.jsonl');
      final store = HistoryStore._(file);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final l in lines.skip(lines.length > _keep ? lines.length - _keep : 0)) {
          try {
            store.hands.add(HandHistory.decode(l));
          } catch (_) {
            // Skip corrupt lines.
          }
        }
      }
      return store;
    } catch (_) {
      return HistoryStore._(null);
    }
  }

  factory HistoryStore.memory() => HistoryStore._(null);

  /// Permanently deletes every saved hand (and with it all statistics).
  Future<void> clear() async {
    hands.clear();
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Fall back to emptying it.
      try {
        await f.writeAsString('', flush: true);
      } catch (_) {}
    }
  }


  /// Adds imported hands, skipping any already saved (same site and hand
  /// number). Returns how many were new.
  Future<int> addAll(Iterable<HandHistory> incoming) async {
    final seen = {for (final h in hands) if (h.sourceId != null) '${h.source}:${h.sourceId}'};
    final fresh = [
      for (final h in incoming)
        if (h.sourceId == null || seen.add('${h.source}:${h.sourceId}')) h,
    ];
    if (fresh.isEmpty) return 0;
    hands
      ..addAll(fresh)
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    if (hands.length > _keep) hands.removeRange(0, hands.length - _keep);
    final f = _file;
    if (f != null) {
      try {
        await f.writeAsString(fresh.map((h) => '${h.encode()}\n').join(), mode: FileMode.append, flush: true);
      } catch (_) {}
    }
    return fresh.length;
  }
  Future<void> add(HandHistory h) async {
    hands.add(h);
    if (hands.length > _keep) hands.removeAt(0);
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString('${h.encode()}\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // History is best-effort.
    }
  }
}
