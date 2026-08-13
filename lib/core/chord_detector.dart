/// Pure chord-quality detection from a set of recently-heard pitch
/// classes (0=C .. 11=B, ignoring octave).
///
/// Kept dependency-free and pure (no Flutter imports) so it's directly
/// unit-testable, matching the project convention set by
/// [MusicUtils] and [PitchDetector].
///
/// HOW IT WORKS:
/// Polyphonic pitch detection (hearing a full chord at once) is a much
/// harder problem than the single-note YIN detection the rest of this
/// app uses. Rather than require a separate polyphonic pitch-detection
/// algorithm, this detector takes a rolling window of recently-detected
/// single notes (e.g. the last ~2 seconds of YIN readings while
/// strumming through a chord one-ish note at a time, or arpeggiating)
/// and matches the *set* of distinct pitch classes heard against known
/// chord interval patterns. This mirrors how the reference app's
/// "Chord Matrix" behaves — it lights up a cell once enough of a
/// chord's notes have been heard close together in time.
library chord_detector;

enum ChordQuality { maj, maj7, dom7, min, min7, dim7 }

extension ChordQualityLabel on ChordQuality {
  String get label {
    switch (this) {
      case ChordQuality.maj:
        return 'maj';
      case ChordQuality.maj7:
        return 'maj7';
      case ChordQuality.dom7:
        return 'dom7';
      case ChordQuality.min:
        return 'min';
      case ChordQuality.min7:
        return 'min7';
      case ChordQuality.dim7:
        return 'dim7';
    }
  }
}

class DetectedChord {
  /// Root pitch class, 0=C .. 11=B.
  final int rootPitchClass;
  final ChordQuality quality;

  /// 0..1 — fraction of the chord's defining intervals that were
  /// actually observed. Used to drive the matrix cell's brightness,
  /// matching the reference app's fading/brightening squares.
  final double confidence;

  const DetectedChord({
    required this.rootPitchClass,
    required this.quality,
    required this.confidence,
  });
}

class ChordDetector {
  ChordDetector._();

  static const List<String> pitchClassNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// Interval patterns (semitones from root) that define each quality.
  /// Listed root-position; [_bestMatch] tries every rotation as a
  /// candidate root since a strummed chord gives no information about
  /// which note is "the" root beyond which one is lowest.
  static const Map<ChordQuality, List<int>> _patterns = {
    ChordQuality.maj: [0, 4, 7],
    ChordQuality.min: [0, 3, 7],
    ChordQuality.maj7: [0, 4, 7, 11],
    ChordQuality.dom7: [0, 4, 7, 10],
    ChordQuality.min7: [0, 3, 7, 10],
    ChordQuality.dim7: [0, 3, 6, 9],
  };

  /// Given a set of recently-heard pitch classes (e.g. from a rolling
  /// window of YIN readings), returns the best-matching chord, or null
  /// if fewer than 3 distinct pitch classes have been heard (can't
  /// reasonably call anything a "chord" below a triad) or nothing
  /// matches well enough.
  static DetectedChord? detect(Set<int> heardPitchClasses,
      {double minConfidence = 0.65}) {
    if (heardPitchClasses.length < 3) return null;

    DetectedChord? best;

    for (int root = 0; root < 12; root++) {
      for (final entry in _patterns.entries) {
        final pattern = entry.value;
        final required = pattern.map((iv) => (root + iv) % 12).toSet();

        // How many of this chord's defining notes were actually heard?
        final int matched =
            required.where(heardPitchClasses.contains).length;
        final double confidence = matched / required.length;

        // Penalize extra/unrelated notes a little so a noisy window
        // doesn't equally "match" every chord that happens to share a
        // subset of pitch classes with whatever was played.
        final int extras =
            heardPitchClasses.difference(required).length;
        final double adjusted =
            confidence - (extras * 0.08).clamp(0.0, 0.3);

        if (adjusted < minConfidence) continue;
        if (best == null || adjusted > best.confidence) {
          best = DetectedChord(
            rootPitchClass: root,
            quality: entry.key,
            confidence: adjusted.clamp(0.0, 1.0),
          );
        }
      }
    }

    return best;
  }
}
