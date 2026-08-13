import 'package:equatable/equatable.dart';

import 'tuning.dart';

/// How close the current reading is to the target note. Used to drive
/// color/feedback in the UI (and could drive haptics/sound too).
enum InTuneStatus { silent, tooLow, inTune, tooHigh }

extension InTuneStatusX on InTuneStatus {
  static InTuneStatus fromCents(double? cents, {double tolerance = 5}) {
    if (cents == null) return InTuneStatus.silent;
    if (cents.abs() <= tolerance) return InTuneStatus.inTune;
    return cents < 0 ? InTuneStatus.tooLow : InTuneStatus.tooHigh;
  }
}

/// A single smoothed, UI-ready tuner reading.
///
/// Extends [Equatable] so the Cubit only emits (and the UI only
/// rebuilds) when something actually changed — `flutter_bloc`'s
/// `BlocBuilder` skips rebuilds for states that compare equal.
class TunerReading extends Equatable {
  final double? frequency;
  final String? noteName;
  final int? octave;

  /// Cents deviation from the *closest standard semitone* (chromatic),
  /// always populated when [frequency] is non-null.
  final double? cents;

  /// If an instrument tuning is active, the string we matched the
  /// reading against (closest target by frequency). Null in chromatic
  /// mode or when there's no signal.
  final StringTarget? matchedString;

  /// Cents deviation from [matchedString]'s frequency specifically —
  /// this is what should drive the needle when a tuning is selected,
  /// since it reflects the actual tuning target rather than the nearest
  /// chromatic semitone.
  final double? centsFromTarget;

  final InTuneStatus status;

  /// Root-mean-square amplitude of the audio window that produced this
  /// reading. Range is roughly 0.0 (silence) to 1.0 (full scale).
  /// Used by the spectrogram to scale spike thickness — louder notes
  /// produce wider, more prominent spikes.
  final double amplitude;

  const TunerReading({
    this.frequency,
    this.noteName,
    this.octave,
    this.cents,
    this.matchedString,
    this.centsFromTarget,
    this.status = InTuneStatus.silent,
    this.amplitude = 0.0,
  });

  static const TunerReading silent = TunerReading(status: InTuneStatus.silent);

  String? get displayName => noteName == null ? null : '$noteName$octave';

  @override
  List<Object?> get props => [
        frequency,
        noteName,
        octave,
        cents,
        matchedString,
        centsFromTarget,
        status,
        amplitude,
      ];
}
