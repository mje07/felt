import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:poker_engine/poker_engine.dart';

/// Progress of a solve.
class SolveProgress {
  const SolveProgress({
    required this.iterations,
    required this.exploitability,
    required this.elapsed,
    this.done = false,
    this.fromCache = false,
  });
  final int iterations;

  /// % of the pot a perfect opponent could win (lower is better).
  final double exploitability;
  final Duration elapsed;
  final bool done, fromCache;
}

/// Runs the solver in a background isolate that keeps the solved tree, so
/// the UI can explore it without copying it or freezing.
class SolverWorker {
  SolverWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final Stream<Object?> _replies;
  int _nextId = 0;

  static Future<SolverWorker> spawn() async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_main, inbox.sendPort);
    final replies = inbox.asBroadcastStream();
    final send = await replies.first as SendPort;
    return SolverWorker._(isolate, send, replies);
  }

  /// Where solved spots are cached (null: no caching, e.g. in tests).
  static Future<String?> defaultCacheDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}solves');
      await dir.create(recursive: true);
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  /// Solves [spot] until the strategy is within [target]% of the pot of
  /// unexploitable, or [maxTime] passes, or [stop] is called. Loads from the
  /// cache when this exact spot was solved before.
  Stream<SolveProgress> solve(SolverSpot spot,
      {double target = 0.5, Duration maxTime = const Duration(minutes: 3), String? cacheDir}) {
    final id = _nextId++;
    final file = cacheDir == null
        ? null
        : '$cacheDir${Platform.pathSeparator}${sha256.convert(utf8.encode(spot.describe()))}.bin';
    _send.send(('solve', id, spot, target, maxTime.inMilliseconds, file));
    final out = StreamController<SolveProgress>();
    late StreamSubscription<Object?> sub;
    sub = _replies.listen((m) {
      if (m is (int, SolveProgress) && m.$1 == id) {
        out.add(m.$2);
        if (m.$2.done) {
          sub.cancel();
          out.close();
        }
      }
    });
    return out.stream;
  }

  void stop() => _send.send(('stop',));

  /// The node reached by following child indices [path] from the root.
  Future<SolverNodeView> view(List<int> path) async {
    final id = _nextId++;
    _send.send(('view', id, path));
    final reply = await _replies.firstWhere((m) => m is (int, SolverNodeView) && m.$1 == id);
    return (reply! as (int, SolverNodeView)).$2;
  }

  void dispose() => _isolate.kill(priority: Isolate.immediate);

  // ------------------------------------------------------------ isolate side

  static Future<void> _main(SendPort out) async {
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    Solver? solver;
    var stopRequested = false;
    await for (final msg in inbox) {
      switch (msg) {
        case ('stop',):
          stopRequested = true;
        case ('view', final int id, final List<int> path):
          final s = solver;
          if (s != null) out.send((id, s.view(path)));
        case ('solve', final int id, final SolverSpot spot, final double target, final int maxMs, final String? file):
          stopRequested = false;
          final sw = Stopwatch()..start();
          final s = Solver(spot);
          solver = s;
          if (file != null && File(file).existsSync()) {
            final bytes = File(file).readAsBytesSync();
            if (s.importStrategies(Float32List.sublistView(Uint8List.fromList(bytes)))) {
              out.send((id, SolveProgress(
                iterations: s.iterations, exploitability: double.nan, elapsed: sw.elapsed, done: true, fromCache: true)));
              continue;
            }
          }
          var expl = double.infinity;
          // Iterate in small chunks, yielding so a stop request can arrive.
          unawaited(() async {
            while (true) {
              s.iterate(s.iterations < 40 ? 5 : 15);
              if (s.iterations % 30 < 15 || s.iterations < 40) expl = s.exploitability();
              final finished = expl <= target || sw.elapsedMilliseconds >= maxMs || stopRequested;
              if (finished) expl = s.exploitability();
              out.send((id, SolveProgress(
                  iterations: s.iterations, exploitability: expl, elapsed: sw.elapsed, done: finished)));
              if (finished) {
                if (file != null && !stopRequested) {
                  try {
                    File(file).writeAsBytesSync(s.exportStrategies().buffer.asUint8List());
                  } catch (_) {}
                }
                return;
              }
              await Future<void>.delayed(Duration.zero);
              if (!identical(solver, s)) return; // a new solve replaced this one
            }
          }());
      }
    }
  }
}
