// Synthesizes the app's sound effects into assets/sounds/*.wav.
// Procedural so there are no third-party sample licences to worry about.
// Run: dart tool/gen_sounds.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const fs = 44100;
final _rng = Random(7);

Float64List buffer(double seconds) => Float64List((seconds * fs).round());

double noise() => _rng.nextDouble() * 2 - 1;

/// RBJ biquad band-pass, applied in place.
void bandpass(Float64List x, double f, double q) {
  final w0 = 2 * pi * f / fs, alpha = sin(w0) / (2 * q);
  final a0 = 1 + alpha, a1 = -2 * cos(w0) / a0, a2 = (1 - alpha) / a0;
  final b0 = alpha / a0, b2 = -alpha / a0;
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final y = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x[i];
    y2 = y1;
    y1 = y;
    x[i] = y;
  }
}

void lowpass(Float64List x, double fc) {
  final a = 1 - exp(-2 * pi * fc / fs);
  var y = 0.0;
  for (var i = 0; i < x.length; i++) {
    y += a * (x[i] - y);
    x[i] = y;
  }
}

/// Adds a filtered noise burst starting at [t] seconds.
void burst(Float64List out, double t, {required double f, double q = 0.8, double tau = 0.015, double gain = 1, double attack = 0.002}) {
  final n = (tau * 8 * fs).round();
  final b = Float64List(n);
  for (var i = 0; i < n; i++) {
    final s = i / fs;
    final env = (s < attack ? s / attack : 1.0) * exp(-s / tau);
    b[i] = noise() * env;
  }
  bandpass(b, f, q);
  _mix(out, b, t, gain);
}

/// Adds a damped sinusoid.
void tone(Float64List out, double t, double f, {double tau = 0.2, double gain = 1, double attack = 0.003}) {
  final n = min((tau * 7 * fs).round(), out.length);
  final start = (t * fs).round();
  for (var i = 0; i < n && start + i < out.length; i++) {
    final s = i / fs;
    final env = (s < attack ? s / attack : 1.0) * exp(-s / tau);
    out[start + i] += sin(2 * pi * f * s) * env * gain;
  }
}

/// A single ceramic chip "clack": a few inharmonic damped modes plus a tick.
void clack(Float64List out, double t, {double gain = 1}) {
  final v = 0.94 + _rng.nextDouble() * 0.12;
  for (final (f, tau, g) in [(2350.0, 0.010, 0.6), (3300.0, 0.008, 1.0), (4750.0, 0.006, 0.7), (6200.0, 0.004, 0.4)]) {
    tone(out, t, f * v, tau: tau, gain: g * gain, attack: 0.0004);
  }
  burst(out, t, f: 5000, q: 0.7, tau: 0.0015, gain: 1.2 * gain, attack: 0.0002);
}

/// Soft bell: fundamental plus a quickly fading inharmonic partial.
void bell(Float64List out, double t, double f, {double gain = 1, double tau = 0.32}) {
  tone(out, t, f, tau: tau, gain: gain, attack: 0.004);
  tone(out, t, f * 2, tau: tau * 0.5, gain: gain * 0.22, attack: 0.004);
  tone(out, t, f * 2.76, tau: tau * 0.25, gain: gain * 0.12, attack: 0.002);
}

void _mix(Float64List out, Float64List src, double t, double gain) {
  final start = (t * fs).round();
  for (var i = 0; i < src.length && start + i < out.length; i++) {
    out[start + i] += src[i] * gain;
  }
}

void write(String name, Float64List x, {double peak = 0.8}) {
  var m = 0.0;
  for (final v in x) {
    m = max(m, v.abs());
  }
  final scale = m == 0 ? 0 : peak / m;
  final fade = (0.006 * fs).round();
  final pcm = Int16List(x.length);
  for (var i = 0; i < x.length; i++) {
    var v = x[i] * scale;
    if (i > x.length - fade) v *= (x.length - i) / fade;
    pcm[i] = (v.clamp(-1.0, 1.0) * 32767).round();
  }
  final data = pcm.buffer.asUint8List();
  final h = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + data.length, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, fs, Endian.little)
    ..setUint32(28, fs * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, data.length, Endian.little);
  final f = File('assets/sounds/$name.wav')..createSync(recursive: true);
  f.writeAsBytesSync([...h.buffer.asUint8List(), ...data]);
  stdout.writeln('assets/sounds/$name.wav  ${(x.length / fs * 1000).round()} ms');
}

void main() {
  // Card sliding off the deck.
  final deal = buffer(0.12);
  burst(deal, 0, f: 3600, q: 0.9, tau: 0.018, attack: 0.004);
  burst(deal, 0.004, f: 1400, q: 1.2, tau: 0.01, gain: 0.35);
  write('deal', deal, peak: 0.55);

  // Card turned over: two quick snaps.
  final flip = buffer(0.12);
  burst(flip, 0, f: 2600, q: 1.0, tau: 0.007);
  burst(flip, 0.032, f: 3200, q: 1.0, tau: 0.011, gain: 0.7);
  write('flip', flip, peak: 0.5);

  // A small bet: three chips clicking onto each other.
  final chip = buffer(0.2);
  clack(chip, 0);
  clack(chip, 0.045, gain: 0.75);
  clack(chip, 0.082, gain: 0.5);
  write('chip', chip, peak: 0.6);

  // Chips swept into the pot / pushed to a winner.
  final collect = buffer(0.48);
  for (var i = 0; i < 9; i++) {
    clack(collect, 0.02 + i * 0.038 + _rng.nextDouble() * 0.015, gain: 0.45 + _rng.nextDouble() * 0.55);
  }
  lowpass(collect, 9000);
  write('collect', collect, peak: 0.6);

  // Knock-knock on the felt for a check.
  final check = buffer(0.26);
  for (final t in [0.0, 0.1]) {
    tone(check, t, 170, tau: 0.028, gain: 1.0, attack: 0.001);
    tone(check, t, 92, tau: 0.04, gain: 0.8, attack: 0.001);
    final click = buffer(0.02);
    burst(click, 0, f: 900, q: 0.7, tau: 0.003);
    _mix(check, click, t, 0.6);
  }
  write('check', check, peak: 0.65);

  // Soft swoosh for a fold: noise with a falling band-pass.
  final fold = buffer(0.22);
  const segs = 8;
  for (var s = 0; s < segs; s++) {
    final seg = Float64List((0.22 / segs * fs).round() + 400);
    for (var i = 0; i < seg.length; i++) {
      seg[i] = noise();
    }
    bandpass(seg, 1700 - s * 140, 0.9);
    final start = s * 0.22 / segs;
    final startIdx = (start * fs).round();
    for (var i = 0; i < seg.length && startIdx + i < fold.length; i++) {
      final p = (startIdx + i) / fold.length;
      fold[startIdx + i] += seg[i] * sin(pi * p) * sin(pi * p);
    }
  }
  lowpass(fold, 4000);
  write('fold', fold, peak: 0.35);

  // Gentle two-note chime when it's your turn.
  final turn = buffer(0.75);
  bell(turn, 0, 1318.5, gain: 1, tau: 0.22);
  bell(turn, 0.11, 1975.5, gain: 0.8, tau: 0.28);
  write('turn', turn, peak: 0.3);

  // Rising arpeggio for winning a pot.
  final win = buffer(1.1);
  for (final (i, f) in [1046.5, 1318.5, 1568.0, 2093.0].indexed) {
    bell(win, i * 0.075, f, gain: 1 - i * 0.12, tau: 0.38);
  }
  write('win', win, peak: 0.35);
}
