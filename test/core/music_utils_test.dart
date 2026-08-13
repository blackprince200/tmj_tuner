import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_app/core/music_utils.dart';

double centsToRatio(double cents) => math.pow(2, cents / 1200).toDouble();

void main() {
  group('MusicUtils.frequencyToNote', () {
    test('A4 = 440Hz is exactly A4 with 0 cents', () {
      final note = MusicUtils.frequencyToNote(440.0);
      expect(note.name, 'A');
      expect(note.octave, 4);
      expect(note.midiNumber, 69);
      expect(note.cents, closeTo(0, 0.01));
    });

    test('standard guitar low E (E2 = 82.41Hz)', () {
      final note = MusicUtils.frequencyToNote(82.41);
      expect(note.name, 'E');
      expect(note.octave, 2);
      // 82.41 is the rounded standard reference; allow a few cents of
      // slack since the "true" E2 is 82.4069...Hz.
      expect(note.cents.abs(), lessThan(5));
    });

    test('standard guitar high E (E4 = 329.63Hz)', () {
      final note = MusicUtils.frequencyToNote(329.63);
      expect(note.name, 'E');
      expect(note.octave, 4);
      expect(note.cents.abs(), lessThan(5));
    });

    test('A3 = 220Hz (exactly one octave below A4)', () {
      final note = MusicUtils.frequencyToNote(220.0);
      expect(note.name, 'A');
      expect(note.octave, 3);
      expect(note.midiNumber, 57);
      expect(note.cents, closeTo(0, 0.01));
    });

    test('slightly sharp frequency reports small positive cents', () {
      final freq = 440.0 * centsToRatio(10);
      final note = MusicUtils.frequencyToNote(freq);
      expect(note.name, 'A');
      expect(note.cents, closeTo(10, 0.5));
    });

    test('slightly flat frequency reports small negative cents', () {
      final freq = 440.0 * centsToRatio(-10);
      final note = MusicUtils.frequencyToNote(freq);
      expect(note.name, 'A');
      expect(note.cents, closeTo(-10, 0.5));
    });

    test('respects a custom A4 calibration reference (442Hz)', () {
      final note = MusicUtils.frequencyToNote(442.0, a4Frequency: 442.0);
      expect(note.name, 'A');
      expect(note.octave, 4);
      expect(note.cents, closeTo(0, 0.01));
    });

    test('a frequency tuned to 440Hz but calibrated against 442Hz is flat', () {
      final note = MusicUtils.frequencyToNote(440.0, a4Frequency: 442.0);
      expect(note.cents, lessThan(0));
    });

    test('throws ArgumentError for zero frequency', () {
      expect(() => MusicUtils.frequencyToNote(0), throwsArgumentError);
    });

    test('throws ArgumentError for negative frequency', () {
      expect(() => MusicUtils.frequencyToNote(-100), throwsArgumentError);
    });

    test('throws ArgumentError for NaN frequency', () {
      expect(() => MusicUtils.frequencyToNote(double.nan), throwsArgumentError);
    });

    test('low bass frequency (E1 = 41.20Hz) resolves correctly without negative-modulo bugs', () {
      // Regression guard: the MIDI number here is well below 69, which
      // is exactly the kind of input that breaks in languages where
      // `%` can return negative results. Dart's `%` is Euclidean for a
      // positive divisor, so this must resolve to a valid note index.
      final note = MusicUtils.frequencyToNote(41.20);
      expect(note.name, 'E');
      expect(note.octave, 1);
      expect(MusicUtils.noteNames.contains(note.name), isTrue);
    });

    test('very low chromatic-mode frequency (30Hz) does not crash or return garbage', () {
      final note = MusicUtils.frequencyToNote(30.0);
      expect(MusicUtils.noteNames.contains(note.name), isTrue);
      expect(note.frequency, 30.0);
    });
  });

  group('MusicUtils.midiToFrequency', () {
    test('MIDI 69 (A4) returns 440Hz at default calibration', () {
      expect(MusicUtils.midiToFrequency(69), closeTo(440.0, 0.001));
    });

    test('MIDI 57 (A3) returns 220Hz', () {
      expect(MusicUtils.midiToFrequency(57), closeTo(220.0, 0.001));
    });

    test('round-trips with frequencyToNote', () {
      const midi = 64;
      final freq = MusicUtils.midiToFrequency(midi);
      final note = MusicUtils.frequencyToNote(freq);
      expect(note.midiNumber, midi);
      expect(note.cents, closeTo(0, 0.01));
    });
  });

  group('MusicUtils.centsBetween', () {
    test('identical frequencies are 0 cents apart', () {
      expect(MusicUtils.centsBetween(220.0, 220.0), closeTo(0, 0.0001));
    });

    test('one octave above is exactly 1200 cents', () {
      expect(MusicUtils.centsBetween(440.0, 220.0), closeTo(1200, 0.01));
    });

    test('one octave below is exactly -1200 cents', () {
      expect(MusicUtils.centsBetween(220.0, 440.0), closeTo(-1200, 0.01));
    });

    test('throws for non-positive input', () {
      expect(() => MusicUtils.centsBetween(0, 100), throwsArgumentError);
      expect(() => MusicUtils.centsBetween(100, 0), throwsArgumentError);
    });
  });
}
