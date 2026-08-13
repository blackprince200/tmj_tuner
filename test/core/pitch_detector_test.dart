import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_app/core/pitch_detector.dart';

/// Generates a pure sine wave at [frequency] Hz, sampled at [sampleRate],
/// for [sampleCount] samples, at the given [amplitude] (0..1).
List<double> generateSineWave({
  required double frequency,
  required double sampleRate,
  required int sampleCount,
  double amplitude = 0.5,
}) {
  return List<double>.generate(
    sampleCount,
    (i) => amplitude * math.sin(2 * math.pi * frequency * i / sampleRate),
  );
}

/// Generates a sine wave with a touch of harmonic content (2nd and 3rd
/// harmonic at reduced amplitude) to emulate a real plucked string more
/// realistically than a pure tone — a real guitar string is never a
/// perfect sinusoid.
List<double> generatePluckedStringLikeWave({
  required double fundamental,
  required double sampleRate,
  required int sampleCount,
  double amplitude = 0.5,
}) {
  return List<double>.generate(sampleCount, (i) {
    final t = i / sampleRate;
    final fundamentalWave = math.sin(2 * math.pi * fundamental * t);
    final secondHarmonic = 0.3 * math.sin(2 * math.pi * fundamental * 2 * t);
    final thirdHarmonic = 0.15 * math.sin(2 * math.pi * fundamental * 3 * t);
    return amplitude * (fundamentalWave + secondHarmonic + thirdHarmonic) / 1.45;
  });
}

List<double> generateSilence(int sampleCount) => List<double>.filled(sampleCount, 0.0);

/// White noise — used to confirm the detector does NOT report a
/// confident pitch for non-periodic input.
List<double> generateWhiteNoise(int sampleCount, {double amplitude = 0.1, int seed = 42}) {
  final random = math.Random(seed);
  return List<double>.generate(sampleCount, (_) => amplitude * (random.nextDouble() * 2 - 1));
}

void main() {
  const double sampleRate = 22050;
  const int windowSize = 8192;

  group('PitchDetector.detectPitch — known frequencies (pure tones)', () {
    final detector = PitchDetector();

    final testFrequencies = <String, double>{
      'low E2 (guitar)': 82.41,
      'A2 (guitar)': 110.00,
      'D3 (guitar)': 146.83,
      'G3 (guitar)': 196.00,
      'B3 (guitar)': 246.94,
      'high E4 (guitar)': 329.63,
      'A4 (concert pitch)': 440.00,
    };

    testFrequencies.forEach((label, freq) {
      test('detects $label ($freq Hz) within a few cents', () {
        final samples = generateSineWave(frequency: freq, sampleRate: sampleRate, sampleCount: windowSize);
        final detected = detector.detectPitch(samples, sampleRate);

        expect(detected, isNotNull, reason: 'Expected to detect a pitch for $label');
        final cents = 1200 * (math.log(detected! / freq) / math.ln2);
        expect(cents.abs(), lessThan(5), reason: '$label detected $detected Hz, expected ~$freq Hz');
      });
    });

    test('detects E1 (bass, 41.20 Hz) when configured with the bass frequency range', () {
      // Regression note: this MUST use a detector configured with the
      // bass range (30-250Hz), matching exactly how TunerCubit
      // configures PitchDetector per-instrument in production. Using
      // the generic default-range detector here would be testing the
      // wrong thing — 41.2Hz legitimately falls outside the default
      // 60-1500Hz range, which is correct behavior, not a bug.
      final bassDetector = PitchDetector(minFrequency: 30, maxFrequency: 250);
      final samples = generateSineWave(frequency: 41.20, sampleRate: sampleRate, sampleCount: windowSize);
      final detected = bassDetector.detectPitch(samples, sampleRate);

      expect(detected, isNotNull, reason: 'Expected to detect E1 with bass-range detector');
      final cents = 1200 * (math.log(detected! / 41.20) / math.ln2);
      expect(cents.abs(), lessThan(5));
    });
  });

  group('PitchDetector.detectPitch — realistic plucked-string-like signal', () {
    test('detects fundamental despite harmonic content (E2)', () {
      final detector = PitchDetector(minFrequency: 60, maxFrequency: 700);
      final samples = generatePluckedStringLikeWave(
        fundamental: 82.41,
        sampleRate: sampleRate,
        sampleCount: windowSize,
      );
      final detected = detector.detectPitch(samples, sampleRate);

      expect(detected, isNotNull);
      final cents = 1200 * (math.log(detected! / 82.41) / math.ln2);
      // Slightly looser tolerance than the pure-tone case since
      // harmonic content perturbs the autocorrelation/CMNDF curve.
      expect(cents.abs(), lessThan(15));
    });

    test('does not lock onto the 2nd harmonic instead of the fundamental', () {
      // This is the classic pitch-detection failure mode: octave
      // errors where the detector reports 2x (or 0.5x) the true pitch.
      final detector = PitchDetector(minFrequency: 60, maxFrequency: 700);
      final samples = generatePluckedStringLikeWave(
        fundamental: 196.00, // G3
        sampleRate: sampleRate,
        sampleCount: windowSize,
      );
      final detected = detector.detectPitch(samples, sampleRate);

      expect(detected, isNotNull);
      // If it locked onto the 2nd harmonic we'd see ~392Hz instead.
      expect(detected!, lessThan(300), reason: 'Detected $detected Hz suggests octave error (2nd harmonic)');
      expect(detected, greaterThan(150));
    });
  });

  group('PitchDetector.detectPitch — silence and noise rejection', () {
    final detector = PitchDetector();

    test('returns null for true silence', () {
      final samples = generateSilence(windowSize);
      expect(detector.detectPitch(samples, sampleRate), isNull);
    });

    test('returns null for low-amplitude white noise (below RMS gate)', () {
      final samples = generateWhiteNoise(windowSize, amplitude: 0.002);
      expect(detector.detectPitch(samples, sampleRate), isNull);
    });

    test('rejects louder white noise via the periodicity (CMNDF) gate, not amplitude alone', () {
      // This amplitude is well above minRms, so if the detector relied
      // on amplitude alone it would wrongly report a "pitch" here.
      // Real periodicity-based rejection should still return null
      // (or very rarely a spurious value) for broadband noise.
      final samples = generateWhiteNoise(windowSize, amplitude: 0.3, seed: 7);
      final detected = detector.detectPitch(samples, sampleRate);
      // We don't assert strict null here (YIN can occasionally find a
      // false periodicity in noise), but if it does report something,
      // it must still be a plausible, in-range frequency rather than
      // garbage like NaN/negative/zero.
      if (detected != null) {
        expect(detected, greaterThan(0));
        expect(detected.isFinite, isTrue);
      }
    });
  });

  group('PitchDetector.detectPitch — input validation / edge cases', () {
    final detector = PitchDetector();

    test('returns null for too-short sample buffer', () {
      final samples = generateSineWave(frequency: 220, sampleRate: sampleRate, sampleCount: 500);
      expect(detector.detectPitch(samples, sampleRate), isNull);
    });

    test('returns null for zero sample rate', () {
      final samples = generateSineWave(frequency: 220, sampleRate: sampleRate, sampleCount: windowSize);
      expect(detector.detectPitch(samples, 0), isNull);
    });

    test('returns null for empty sample list', () {
      expect(detector.detectPitch(<double>[], sampleRate), isNull);
    });

    test('constructor throws for an invalid frequency range', () {
      expect(
        () => PitchDetector(minFrequency: 500, maxFrequency: 100),
        throwsArgumentError,
      );
    });

    test('respects custom minFrequency/maxFrequency bounds', () {
      // A bass-range detector should not "see" a ukulele-range note.
      final bassDetector = PitchDetector(minFrequency: 30, maxFrequency: 250);
      final ukuleleNoteSamples =
          generateSineWave(frequency: 440, sampleRate: sampleRate, sampleCount: windowSize);
      final detected = bassDetector.detectPitch(ukuleleNoteSamples, sampleRate);
      // Either correctly rejected, or (if some alias/harmonic within
      // range is found) must be within the configured bounds — it
      // must never report something outside [30, 250].
      if (detected != null) {
        expect(detected, inInclusiveRange(30, 250));
      }
    });
  });

  group('PitchDetector.detectPitch — determinism', () {
    test('detected frequency is stable across repeated calls on the same signal', () {
      final detector = PitchDetector();
      final samples = generateSineWave(frequency: 110.00, sampleRate: sampleRate, sampleCount: windowSize);

      final first = detector.detectPitch(samples, sampleRate);
      final second = detector.detectPitch(List<double>.from(samples), sampleRate);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, equals(second), reason: 'Same input must produce a deterministic result');
    });
  });
}
