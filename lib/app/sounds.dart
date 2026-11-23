import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'settings.dart';

enum Sfx {
  deal(0.55),
  flip(0.6),
  chip(0.7),
  collect(0.7),
  check(0.8),
  fold(0.6),
  turn(0.55),
  win(0.6);

  const Sfx(this.level);

  /// Relative loudness, mixed under the user's master volume.
  final double level;
}

/// Plays short UI/game sound effects.
abstract interface class Sounds {
  void play(Sfx sfx);

  /// No-op implementation (tests, or when audio fails to start).
  static const Sounds silent = _Silent();
}

class _Silent implements Sounds {
  const _Silent();
  @override
  void play(Sfx sfx) {}
}

/// Low-latency playback through SoLoud (miniaudio), on Windows and Linux.
class SoloudSounds implements Sounds {
  SoloudSounds._(this._settings, this._sources);

  final Settings _settings;
  final Map<Sfx, AudioSource> _sources;

  /// Starts the audio engine and preloads every effect. Falls back to
  /// [Sounds.silent] if the device has no usable audio output.
  static Future<Sounds> start(Settings settings) async {
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init();
      final sources = <Sfx, AudioSource>{};
      for (final s in Sfx.values) {
        sources[s] = await soloud.loadAsset('assets/sounds/${s.name}.wav');
      }
      return SoloudSounds._(settings, sources);
    } catch (e) {
      debugPrint('Sound disabled: $e');
      return Sounds.silent;
    }
  }

  @override
  void play(Sfx sfx) {
    if (!_settings.soundEnabled || _settings.volume <= 0) return;
    final src = _sources[sfx];
    if (src == null) return;
    try {
      SoLoud.instance.play(src, volume: sfx.level * _settings.volume);
    } catch (_) {
      // Never let audio break the game.
    }
  }
}

/// Makes [Sounds] available below the app.
class SoundsScope extends InheritedWidget {
  const SoundsScope({super.key, required this.sounds, required super.child});
  final Sounds sounds;

  static Sounds of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SoundsScope>()?.sounds ?? Sounds.silent;

  @override
  bool updateShouldNotify(SoundsScope old) => old.sounds != sounds;
}
