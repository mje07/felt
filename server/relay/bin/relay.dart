import 'dart:io';

import 'package:felt_relay/relay.dart';

/// Runs the relay. Listens on $PORT (default 8080).
Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final relay = Relay();
  await relay.start(port: port);
  stdout.writeln('Felt relay listening on port ${relay.port}');
  ProcessSignal.sigint.watch().listen((_) async {
    await relay.stop();
    exit(0);
  });
}
