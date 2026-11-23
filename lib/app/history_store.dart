import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:poker_engine/poker_engine.dart';

/// Hand histories as JSON lines in the app-support directory.
class HistoryStore {
  HistoryStore._(this._file);

  static const _keep = 500;
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
