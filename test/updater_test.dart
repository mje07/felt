import 'dart:io';

import 'package:felt/app/updater.dart';
import 'package:felt/app/version.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> release({
  String tag = 'v9.0.0',
  String name = 'Felt-Setup-9.0.0.exe',
  String url = 'https://github.com/mje07/felt/releases/download/v9.0.0/Felt-Setup-9.0.0.exe',
  String? digest = 'sha256:b42faf30871e1df64734b955cbf19842d9a48c91e4679bfa1080a34161f7d8ea',
}) =>
    {
      'tag_name': tag,
      'html_url': 'https://github.com/mje07/felt/releases/tag/$tag',
      'assets': [
        {'name': name, 'browser_download_url': url, 'digest': ?digest},
      ],
    };

void main() {
  test('version.dart matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(appVersion, v);
  });

  test('version comparison', () {
    expect(isNewerVersion('1.1.1', '1.1.0'), isTrue);
    expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.1.0', '1.1.0'), isFalse);
    expect(isNewerVersion('1.0.9', '1.1.0'), isFalse);
    expect(isNewerVersion('1.1.0+5', '1.1.0'), isFalse);
    expect(isNewerVersion('banana', '1.0.0'), isFalse);
  });

  group('release parsing only trusts verifiable installers from this repo', () {
    test('a normal release', () {
      final r = parseRelease(release())!;
      expect(r.version, '9.0.0');
      expect(r.hasVerifiableInstaller, isTrue);
      expect(r.sha256, hasLength(64));
    });

    test('rejects installers hosted elsewhere or named oddly', () {
      expect(parseRelease(release(url: 'https://evil.example/Felt-Setup-9.0.0.exe'))!.hasVerifiableInstaller, isFalse);
      expect(parseRelease(release(url: 'https://github.com/someone/else/releases/download/v9/Felt-Setup-9.0.0.exe'))!
          .hasVerifiableInstaller, isFalse);
      expect(parseRelease(release(url: 'http://github.com/mje07/felt/releases/download/v9.0.0/Felt-Setup-9.0.0.exe'))!
          .hasVerifiableInstaller, isFalse);
      expect(parseRelease(release(name: 'Felt-Setup-9.0.0.exe.bat'))!.hasVerifiableInstaller, isFalse);
    });

    test('rejects installers without a SHA-256 digest', () {
      expect(parseRelease(release(digest: null))!.hasVerifiableInstaller, isFalse);
      expect(parseRelease(release(digest: 'md5:abc'))!.hasVerifiableInstaller, isFalse);
    });

    test('ignores malformed tags', () {
      expect(parseRelease(release(tag: 'latest')), isNull);
      expect(parseRelease({'nope': 1}), isNull);
    });
  });

  test('the updater stays offline until started', () async {
    expect(Updater.current.enabled, isFalse);
    await Updater.current.check();
    expect(Updater.current.status, UpdateStatus.idle);
  });
}
