/// Data models describing instruments, their string layouts, and named
/// alternate tunings. Adding a new tuning or instrument is just adding
/// an entry to [TuningLibrary] — no other code changes needed.
library tuning_models;

import 'package:equatable/equatable.dart';

/// A single target string/note, e.g. the low E string on a guitar.
class StringTarget extends Equatable {
  /// Display label, e.g. "E2", "A2".
  final String label;

  /// Target frequency in Hz (at A4 = 440 reference; the ViewModel
  /// re-derives this if the user changes the calibration reference).
  final double frequency;

  const StringTarget({required this.label, required this.frequency});

  /// Returns just the note letter(s) without the octave number,
  /// e.g. "E", "A", "Eb" — used by the string-selector chips.
  String get noteNameOnly => label.replaceAll(RegExp(r'[0-9]'), '');

  @override
  List<Object?> get props => [label, frequency];
}

/// A named tuning for a given instrument, e.g. "Standard" or "Drop D".
class Tuning extends Equatable {
  final String name;
  final List<StringTarget> strings;

  const Tuning({required this.name, required this.strings});

  @override
  List<Object?> get props => [name, strings];
}

enum Instrument { guitar, bass, ukulele, chromatic }

extension InstrumentLabel on Instrument {
  String get label {
    switch (this) {
      case Instrument.guitar:
        return 'Guitar';
      case Instrument.bass:
        return 'Bass';
      case Instrument.ukulele:
        return 'Ukulele';
      case Instrument.chromatic:
        return 'Chromatic';
    }
  }

  /// Frequency search range fed to the pitch detector — narrowing this
  /// per instrument meaningfully improves detection accuracy and speed
  /// by excluding lags YIN would otherwise have to evaluate.
  double get minFrequency {
    switch (this) {
      case Instrument.guitar:
        return 70;
      case Instrument.bass:
        return 30;
      case Instrument.ukulele:
        return 220;
      case Instrument.chromatic:
        return 60;
    }
  }

  double get maxFrequency {
    switch (this) {
      case Instrument.guitar:
        return 700;
      case Instrument.bass:
        return 250;
      case Instrument.ukulele:
        return 900;
      case Instrument.chromatic:
        return 1200;
    }
  }
}

/// Central registry of built-in tunings per instrument. Extend this list
/// freely — the settings UI is generated from it automatically.
class TuningLibrary {
  TuningLibrary._();

  static const Map<Instrument, List<Tuning>> tunings = {
    Instrument.guitar: [
      Tuning(name: 'Standard (EADGBE)', strings: [
        StringTarget(label: 'E2', frequency: 82.41),
        StringTarget(label: 'A2', frequency: 110.00),
        StringTarget(label: 'D3', frequency: 146.83),
        StringTarget(label: 'G3', frequency: 196.00),
        StringTarget(label: 'B3', frequency: 246.94),
        StringTarget(label: 'E4', frequency: 329.63),
      ]),
      Tuning(name: 'Drop D', strings: [
        StringTarget(label: 'D2', frequency: 73.42),
        StringTarget(label: 'A2', frequency: 110.00),
        StringTarget(label: 'D3', frequency: 146.83),
        StringTarget(label: 'G3', frequency: 196.00),
        StringTarget(label: 'B3', frequency: 246.94),
        StringTarget(label: 'E4', frequency: 329.63),
      ]),
      Tuning(name: 'Half-Step Down', strings: [
        StringTarget(label: 'Eb2', frequency: 77.78),
        StringTarget(label: 'Ab2', frequency: 103.83),
        StringTarget(label: 'Db3', frequency: 138.59),
        StringTarget(label: 'Gb3', frequency: 185.00),
        StringTarget(label: 'Bb3', frequency: 233.08),
        StringTarget(label: 'Eb4', frequency: 311.13),
      ]),
      Tuning(name: 'Open G', strings: [
        StringTarget(label: 'D2', frequency: 73.42),
        StringTarget(label: 'G2', frequency: 98.00),
        StringTarget(label: 'D3', frequency: 146.83),
        StringTarget(label: 'G3', frequency: 196.00),
        StringTarget(label: 'B3', frequency: 246.94),
        StringTarget(label: 'D4', frequency: 293.66),
      ]),
      Tuning(name: 'DADGAD', strings: [
        StringTarget(label: 'D2', frequency: 73.42),
        StringTarget(label: 'A2', frequency: 110.00),
        StringTarget(label: 'D3', frequency: 146.83),
        StringTarget(label: 'G3', frequency: 196.00),
        StringTarget(label: 'A3', frequency: 220.00),
        StringTarget(label: 'D4', frequency: 293.66),
      ]),
    ],
    Instrument.bass: [
      Tuning(name: 'Standard 4-String (EADG)', strings: [
        StringTarget(label: 'E1', frequency: 41.20),
        StringTarget(label: 'A1', frequency: 55.00),
        StringTarget(label: 'D2', frequency: 73.42),
        StringTarget(label: 'G2', frequency: 98.00),
      ]),
      Tuning(name: 'Drop D', strings: [
        StringTarget(label: 'D1', frequency: 36.71),
        StringTarget(label: 'A1', frequency: 55.00),
        StringTarget(label: 'D2', frequency: 73.42),
        StringTarget(label: 'G2', frequency: 98.00),
      ]),
    ],
    Instrument.ukulele: [
      Tuning(name: 'Standard (GCEA)', strings: [
        StringTarget(label: 'G4', frequency: 392.00),
        StringTarget(label: 'C4', frequency: 261.63),
        StringTarget(label: 'E4', frequency: 329.63),
        StringTarget(label: 'A4', frequency: 440.00),
      ]),
    ],
    Instrument.chromatic: [
      Tuning(name: 'Any note', strings: []),
    ],
  };

  static List<Tuning> tuningsFor(Instrument instrument) => tunings[instrument] ?? const [];
}
