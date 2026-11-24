import 'dart:async';
import 'dart:isolate';

import 'package:poker_engine/poker_engine.dart';

/// Imports hand-history text in a background isolate (parsing, replaying
/// and grading every decision can take a while), reporting progress.
Future<ImportResult> importInBackground(String text, {required void Function(int done, int total) onProgress}) async {
  final port = ReceivePort();
  final done = Completer<ImportResult>();
  port.listen((m) {
    if (m is (int, int)) {
      onProgress(m.$1, m.$2);
    } else if (m is ImportResult) {
      done.complete(m);
      port.close();
    } else if (m is String) {
      done.completeError(StateError(m));
      port.close();
    }
  });
  await Isolate.spawn(_run, (text, port.sendPort), onError: port.sendPort);
  return done.future;
}

void _run((String, SendPort) args) {
  final (text, out) = args;
  var last = DateTime.now();
  final result = importHandHistories(text, review: true, onProgress: (d, t) {
    final now = DateTime.now();
    if (d == t || now.difference(last).inMilliseconds > 120) {
      last = now;
      out.send((d, t));
    }
  });
  Isolate.exit(out, result);
}

/// A hand's result in big blinds (amounts differ between sites and Felt).
double netBb(HandHistory h) {
  final start = h.events.isEmpty ? null : h.events.first;
  final bb = (start?['bb'] as int?) ?? 0;
  return bb > 0 ? h.heroNet / bb : 0;
}
