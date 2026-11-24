import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'settings.dart';
import 'version.dart';

/// Where releases are published.
const releaseRepo = 'mje07/felt';

enum UpdateStatus {
  /// Not checked yet (or updates are off).
  idle,
  checking,
  upToDate,

  /// A newer installer is downloading in the background.
  downloading,

  /// A verified installer is on disk; it installs on the next launch, or now
  /// via [Updater.installNow].
  ready,

  /// A newer version exists but can't be installed automatically here
  /// (Linux, or a build that wasn't installed with Setup.exe).
  available,
  failed,
}

/// A release as published on GitHub.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.pageUrl,
    this.installerUrl,
    this.installerName,
    this.sha256,
  });
  final String version, pageUrl;
  final String? installerUrl, installerName, sha256;

  bool get hasVerifiableInstaller => installerUrl != null && sha256 != null;
}

/// Parses the GitHub "latest release" API response. Only accepts a Windows
/// installer that lives under this repository's release downloads and has a
/// SHA-256 digest; anything else is ignored.
ReleaseInfo? parseRelease(Map<String, Object?> json, {String repo = releaseRepo}) {
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (parseVersion(version) == null) return null;
  String? url, name, digest;
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is! Map) continue;
      final n = a['name'], u = a['browser_download_url'], d = a['digest'];
      if (n is! String || u is! String) continue;
      if (!RegExp(r'^Felt-Setup-[0-9.]+\.exe$').hasMatch(n)) continue;
      final uri = Uri.tryParse(u);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/$repo/releases/download/')) {
        continue;
      }
      url = u;
      name = n;
      if (d is String && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(d)) digest = d.substring(7);
      break;
    }
  }
  final page = json['html_url'];
  return ReleaseInfo(
    version: version,
    pageUrl: page is String && page.startsWith('https://github.com/$repo/')
        ? page
        : 'https://github.com/$repo/releases/latest',
    installerUrl: url,
    installerName: name,
    sha256: digest,
  );
}

/// "1.2.10" → [1, 2, 10]; null if it isn't a plain dotted version.
List<int>? parseVersion(String v) {
  final core = v.split('+').first;
  if (!RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(core)) return null;
  return [for (final p in core.split('.')) int.parse(p)];
}

/// Whether [candidate] is a later version than [current].
bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 4; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Checks GitHub for new releases and, on Windows installs, downloads and
/// verifies the installer so it can update itself.
///
/// The only network request Felt makes: GitHub's public release API and,
/// when there's an update, the installer download. No data about you or
/// your games is sent.
class Updater extends ChangeNotifier {
  Updater._({required this.enabled, this.settings});

  /// The app-wide updater. Disabled (never touches the network) until
  /// [start] runs, so tests stay offline.
  static Updater current = Updater._(enabled: false);

  final bool enabled;
  final Settings? settings;

  UpdateStatus status = UpdateStatus.idle;
  String? latestVersion;
  String releasePageUrl = 'https://github.com/$releaseRepo/releases/latest';
  double progress = 0;
  String? error;
  String? _installerPath;
  Timer? _timer;

  static const _checkEvery = Duration(hours: 6);

  /// Installs a pending update (this exits the app), otherwise starts
  /// checking in the background. Call once at launch.
  static Future<void> start(Settings settings) async {
    final u = Updater._(enabled: true, settings: settings);
    current = u;
    await u._applyPendingAtLaunch();
    if (settings.autoUpdate) unawaited(u.check());
    u._timer = Timer.periodic(_checkEvery, (_) {
      if (settings.autoUpdate) unawaited(u.check());
    });
  }

  /// Whether this copy was installed by Setup.exe (it can update itself).
  static bool get canSelfUpdate {
    if (!Platform.isWindows) return false;
    final dir = File(Platform.resolvedExecutable).parent.path;
    return File('$dir${Platform.pathSeparator}unins000.exe').existsSync();
  }

  static Future<Directory> _updatesDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}updates');
  }

  Future<void> check() async {
    if (!enabled || status == UpdateStatus.checking || status == UpdateStatus.downloading) return;
    if (status == UpdateStatus.ready) return; // already have it
    _set(UpdateStatus.checking);
    try {
      final release = await _fetchLatest();
      if (release == null || !isNewerVersion(release.version, appVersion)) {
        _set(UpdateStatus.upToDate);
        return;
      }
      latestVersion = release.version;
      releasePageUrl = release.pageUrl;
      if (canSelfUpdate && release.hasVerifiableInstaller) {
        await _download(release);
      } else {
        _set(UpdateStatus.available);
      }
    } catch (e) {
      error = '$e';
      _set(UpdateStatus.failed);
    }
  }

  Future<ReleaseInfo?> _fetchLatest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$releaseRepo/releases/latest'));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Felt-Updater');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) return null; // no releases yet
      if (res.statusCode != 200) throw HttpException('GitHub returned ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join();
      return parseRelease(jsonDecode(body) as Map<String, Object?>);
    } finally {
      client.close();
    }
  }

  Future<void> _download(ReleaseInfo r) async {
    _set(UpdateStatus.downloading);
    progress = 0;
    final dir = await _updatesDir();
    await dir.create(recursive: true);
    final target = File('${dir.path}${Platform.pathSeparator}${r.installerName}');
    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(r.installerUrl!));
      req.headers.set(HttpHeaders.userAgentHeader, 'Felt-Updater');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Download failed (${res.statusCode})');
      final total = res.contentLength;
      final sink = part.openWrite();
      final digestOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestOut);
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      hasher.close();
      if (digestOut.value.toString() != r.sha256) {
        await part.delete();
        throw const FileSystemException('The downloaded installer failed its integrity check');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      await File('${dir.path}${Platform.pathSeparator}pending.json').writeAsString(jsonEncode({
        'version': r.version,
        'file': target.path,
        'sha256': r.sha256,
      }));
      _installerPath = target.path;
      _set(UpdateStatus.ready);
    } finally {
      client.close();
    }
  }

  /// At launch: run a downloaded, still-valid installer for a newer version
  /// (when automatic updates are on), or clean up an old one.
  Future<void> _applyPendingAtLaunch() async {
    try {
      final dir = await _updatesDir();
      final pending = File('${dir.path}${Platform.pathSeparator}pending.json');
      if (!await pending.exists()) return;
      final info = jsonDecode(await pending.readAsString()) as Map<String, Object?>;
      final version = info['version'] as String? ?? '';
      final file = File(info['file'] as String? ?? '');
      if (!isNewerVersion(version, appVersion) || !await file.exists() || !canSelfUpdate) {
        await dir.delete(recursive: true);
        return;
      }
      // Re-verify: the file could have been changed since it was downloaded.
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest != info['sha256']) {
        await dir.delete(recursive: true);
        return;
      }
      latestVersion = version;
      _installerPath = file.path;
      status = UpdateStatus.ready;
      if (settings?.autoUpdate ?? false) await installNow();
    } catch (_) {
      // A broken pending update must never stop the app from starting.
    }
  }

  /// Runs the verified installer silently and quits. The installer replaces
  /// this version and starts the new one when it finishes.
  Future<void> installNow() async {
    final path = _installerPath;
    if (path == null || status != UpdateStatus.ready) return;
    await Process.start(
      path,
      const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RELAUNCH=1'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  void _set(UpdateStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;
  @override
  void add(Digest data) => _value = data;
  @override
  void close() {}
}

/// Opens a web page in the default browser.
Future<void> openInBrowser(String url) async {
  if (!url.startsWith('https://')) return;
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.start('open', [url], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  }
}
