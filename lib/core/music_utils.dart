/// Core music-theory math: converting between frequency (Hz), MIDI note
/// numbers, note names, and "cents" (the unit musicians use for tuning
/// deviation: 100 cents = 1 semitone).
///
/// Kept dependency-free and pure so it's trivially unit-testable — this
/// is one of exactly two files in the app with zero Flutter dependency
/// (the other is [PitchDetector]), by design: it's the highest-risk,
/// highest-value place for unit tests because a silent regression here
/// makes every reading in the app wrong in a way that's hard to notice
/// by eye (e.g. off by one semitone, or cents sign flipped).
library music_utils;

import 'dart:math' as math;

/// Everything the app needs to know about a detected frequency, relative
/// to a chosen A4 calibration reference.
class NoteInfo {
  /// e.g. "C", "C#" — sharps only, no flats (matches [MusicUtils.noteNames]).
  final String name;

  /// Scientific pitch notation octave, e.g. 4 for A4 = 440Hz.
  final int octave;

  /// MIDI note number (A4 = 69).
  final int midiNumber;

  /// Exact frequency of the detected pitch.
  final double frequency;

  /// Frequency of the *nearest* in-tune note.
  final double nearestNoteFrequency;

  /// How far off the detected frequency is from the nearest note,
  /// in cents. Negative = flat (too low), positive = sharp (too high).
  /// Range is roughly -50..+50 since beyond that you're closer to a
  /// different note entirely.
  final double cents;

  const NoteInfo({
    required this.name,
    required this.octave,
    required this.midiNumber,
    required this.frequency,
    required this.nearestNoteFrequency,
    required this.cents,
  });

  String get displayName => '$name$octave';

  @override
  String toString() =>
      'NoteInfo($displayName, ${frequency.toStringAsFixed(2)}Hz, '
      '${cents.toStringAsFixed(1)}c)';

  @override
  bool operator ==(Object other) =>
      other is NoteInfo &&
      other.name == name &&
      other.octave == octave &&
      other.midiNumber == midiNumber &&
      other.frequency == frequency &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(name, octave, midiNumber, frequency, cents);
}

class MusicUtils {
  MusicUtils._();

  static const List<String> noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// Converts a frequency (Hz) into full note information relative to
  /// [a4Frequency] (the calibration reference for A4, normally 440.0Hz —
  /// some orchestras/clients use 442Hz etc., so this is configurable).
  ///
  /// Throws [ArgumentError] for non-positive frequency rather than using
  /// an assert, since asserts are stripped in release builds — a caller
  /// passing 0 or a negative number in production should fail loudly,
  /// not silently produce NaN/garbage through `log()`.
  static NoteInfo frequencyToNote(double frequency, {double a4Frequency = 440.0}) {
    if (frequency <= 0 || frequency.isNaN || frequency.isInfinite) {
      throw ArgumentError.value(frequency, 'frequency', 'must be a finite positive number');
    }
    if (a4Frequency <= 0) {
      throw ArgumentError.value(a4Frequency, 'a4Frequency', 'must be positive');
    }

    // Number of semitones away from A4 (can be fractional).
    final double semitonesFromA4 = 12 * (math.log(frequency / a4Frequency) / math.ln2);

    final int midiNumber = (69 + semitonesFromA4).round();

    // Frequency of the nearest exact semitone.
    final double nearestNoteFrequency =
        a4Frequency * math.pow(2, (midiNumber - 69) / 12);

    // Cents deviation from that nearest note.
    final double cents = 1200 * (math.log(frequency / nearestNoteFrequency) / math.ln2);

    // Dart's `%` is Euclidean (always non-negative for a positive
    // divisor) so this is safe even for very low MIDI numbers — no
    // extra normalization needed here.
    final int noteIndex = midiNumber % 12;
    final int octave = (midiNumber ~/ 12) - 1;

    return NoteInfo(
      name: noteNames[noteIndex],
      octave: octave,
      midiNumber: midiNumber,
      frequency: frequency,
      nearestNoteFrequency: nearestNoteFrequency,
      cents: cents,
    );
  }

  /// Frequency of a given MIDI note number, relative to [a4Frequency].
  static double midiToFrequency(int midiNumber, {double a4Frequency = 440.0}) {
    return a4Frequency * math.pow(2, (midiNumber - 69) / 12);
  }

  /// Signed cents difference between two frequencies (`f` relative to
  /// `reference`). Negative = `f` is flat relative to `reference`.
  /// Centralized here so every call site (provider, closest-string
  /// matching, stability checks) uses identical math — previously this
  /// formula was copy-pasted in three places across the old codebase,
  /// which is exactly how those call sites can silently drift apart.
  static double centsBetween(double f, double reference) {
    if (f <= 0 || reference <= 0) {
      throw ArgumentError('frequencies must be positive');
    }
    return 1200 * (math.log(f / reference) / math.ln2);
  }
}
