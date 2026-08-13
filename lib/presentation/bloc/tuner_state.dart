import 'package:equatable/equatable.dart';

import '../../data/models/detected_pitch.dart';
import '../../data/models/tuning.dart';

/// Everything the View needs to render a frame. Immutable; the Cubit
/// never mutates a TunerState in place, it always emits a new one via
/// `copyWith` — this is what makes Bloc's equality-based rebuild
/// skipping and time-travel debugging possible.
class TunerState extends Equatable {
  final bool isListening;
  final String? errorMessage;
  final TunerReading reading;

  final Instrument instrument;
  final Tuning currentTuning;
  final double a4Reference;
  final double toleranceCents;

  final bool autoMode;
  final StringTarget? selectedString;

  const TunerState({
    required this.isListening,
    required this.errorMessage,
    required this.reading,
    required this.instrument,
    required this.currentTuning,
    required this.a4Reference,
    required this.toleranceCents,
    required this.autoMode,
    required this.selectedString,
  });

  factory TunerState.initial() => TunerState(
        isListening: false,
        errorMessage: null,
        reading: TunerReading.silent,
        instrument: Instrument.guitar,
        currentTuning: TuningLibrary.tuningsFor(Instrument.guitar).first,
        a4Reference: 440.0,
        toleranceCents: 5,
        autoMode: true,
        selectedString: null,
      );

  List<Tuning> get availableTunings => TuningLibrary.tuningsFor(instrument);

  TunerState copyWith({
    bool? isListening,
    String? Function()? errorMessage,
    TunerReading? reading,
    Instrument? instrument,
    Tuning? currentTuning,
    double? a4Reference,
    double? toleranceCents,
    bool? autoMode,
    StringTarget? Function()? selectedString,
  }) {
    return TunerState(
      isListening: isListening ?? this.isListening,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      reading: reading ?? this.reading,
      instrument: instrument ?? this.instrument,
      currentTuning: currentTuning ?? this.currentTuning,
      a4Reference: a4Reference ?? this.a4Reference,
      toleranceCents: toleranceCents ?? this.toleranceCents,
      autoMode: autoMode ?? this.autoMode,
      selectedString: selectedString != null ? selectedString() : this.selectedString,
    );
  }

  @override
  List<Object?> get props => [
        isListening,
        errorMessage,
        reading,
        instrument,
        currentTuning,
        a4Reference,
        toleranceCents,
        autoMode,
        selectedString,
      ];
}
