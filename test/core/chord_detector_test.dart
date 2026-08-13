import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_app/core/chord_detector.dart';

void main() {
  group('ChordDetector', () {
    test('detects a C major triad from its three pitch classes', () {
      // C=0, E=4, G=7
      final chord = ChordDetector.detect({0, 4, 7});
      expect(chord, isNotNull);
      expect(chord!.rootPitchClass, 0);
      expect(chord.quality, ChordQuality.maj);
    });

    test('detects an A minor triad', () {
      // A=9, C=0, E=4
      final chord = ChordDetector.detect({9, 0, 4});
      expect(chord, isNotNull);
      expect(chord!.rootPitchClass, 9);
      expect(chord.quality, ChordQuality.min);
    });

    test('detects a G dominant 7th chord', () {
      // G=7, B=11, D=2, F=5
      final chord = ChordDetector.detect({7, 11, 2, 5});
      expect(chord, isNotNull);
      expect(chord!.rootPitchClass, 7);
      expect(chord.quality, ChordQuality.dom7);
    });

    test('detects a diminished 7th chord', () {
      // B dim7: B=11, D=2, F=5, Ab=8
      final chord = ChordDetector.detect({11, 2, 5, 8});
      expect(chord, isNotNull);
      expect(chord?.quality, ChordQuality.dim7);
    });

    test('returns null with fewer than 3 distinct pitch classes', () {
      expect(ChordDetector.detect({0}), isNull);
      expect(ChordDetector.detect({0, 4}), isNull);
    });

    test('returns null for an unrelated/noisy set of pitch classes', () {
      // No 3+ note subset here forms a recognized triad/seventh pattern.
      final chord = ChordDetector.detect({1, 6, 11});
      expect(chord, isNull);
    });

    test('prefers the chord requiring no unrelated extra notes', () {
      // Exactly a C major triad, nothing else heard.
      final chord = ChordDetector.detect({0, 4, 7});
      expect(chord, isNotNull);
      expect(chord!.confidence, 1.0);
    });
  });
}
