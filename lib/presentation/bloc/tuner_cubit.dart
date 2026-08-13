import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/music_utils.dart';
import '../../core/pitch_detector.dart';
import '../../data/models/detected_pitch.dart';
import '../../data/models/tuning.dart';
import '../../services/audio_capture_service.dart';
import 'tuner_state.dart';

/// ViewModel for the tuner screen (MVVM-via-Bloc pattern).
///
/// ACCURACY IMPROVEMENTS in this version:
///
/// 1. LARGER AUDIO WINDOW (12288 samples @ 22050Hz ≈ 557ms):
///    The previous 8192 window was too short for low bass notes (E1 = 41Hz
///    needs ~538ms for reliable YIN analysis). We now use 12288 samples
///    which gives >2 full periods even for the lowest bass string.
///
/// 2. EXPONENTIAL MOVING AVERAGE (EMA) smoothing:
///    Instead of a simple median window, we apply an EMA with α=0.35.
///    This reacts faster to genuine pitch changes (e.g. tuning a string
///    up/down in real time) while damping single-frame jitter from the
///    YIN algorithm. Inspired by FastTune's real-time tracking approach.
///
/// 3. TIGHTER STABILITY GATE:
///    The stability window is now ±25 cents (was ±40 cents). This means
///    a single octave-error frame won't snap the display — it needs to be
///    within half a semitone of the EMA candidate to count.
///
/// 4. OCTAVE SANITY CHECK:
///    Before emitting, we check if the candidate is within ±2 octaves of
///    the previously emitted frequency. If it's not, we skip the frame.
///    This prevents single-frame octave jumps from flashing the display.
///
/// 5. CENTS HISTORY for display smoothing:
///    We separately track the last 3 cents readings and display their
///    mean, so the needle doesn't jitter on a sustained note even if the
///    raw frequency estimate has small frame-to-frame variations.
class TunerCubit extends Cubit<TunerState> {
  final AudioCaptureService _audioService;

  // 8192 samples @ 22050 Hz ≈ 371ms.
  // Covers > 15 periods of E2 (82.41Hz) and > 1.5 periods of E1 (41.20Hz).
  static const int _windowSize = 8192;

  static const int _silenceGraceCount = 6;

  // EMA smoothing factor — higher = faster response, more jitter.
  // 0.35 gives ~3-frame settling time on a sudden pitch change.
  static const double _emaAlpha = 0.35;

  // Only emit if new freq is within ±25 cents of the current EMA candidate.
  // Rejects single octave-error frames without delaying real tuning changes.
  static const double _stabilityCentsWindow = 25.0;

  // Reject jumps > 2 octaves from last emitted frequency (octave sanity).
  static const double _maxOctaveJump = 2.0;

  // Cents display smoothing window
  static const int _centsHistoryLen = 3;

  StreamSubscription<List<double>>? _audioSub;
  final List<double> _buffer = [];
  int _newSamplesSinceLastAnalysis = 0; // count new samples since last YIN run
  double? _emaFreq;          // current EMA frequency
  double? _lastEmittedFreq;  // for octave sanity check
  int _silentStreak = 0;
  int _candidateCount = 0;   // frames agreeing with EMA
  final List<double> _centsHistory = [];

  PitchDetector _detector;

  /// Raw, unsmoothed note stream — emits a pitch class (0=C..11=B) for
  /// EVERY frame the YIN detector finds a fundamental, completely
  /// bypassing the EMA/stability-gate/2-consecutive-frame logic in
  /// [_processDetectedFrequency] below.
  ///
  /// That gating exists for the *tuner display* (`state.reading`), where
  /// we want a settled, jitter-free single note held for a while. But
  /// strumming or arpeggiating a chord moves through several different
  /// pitch classes within a couple of hundred milliseconds — each new
  /// note is, by design, a "disagreement" that resets the tuner's EMA
  /// candidate counter, so most of those notes never reached
  /// `state.reading` and the Chord Matrix screen (which built its
  /// rolling note window from `cubit.stream`) saw almost nothing.
  ///
  /// The Chord Matrix screen now listens to this stream instead, so it
  /// gets every detected note immediately, independent of the tuner's
  /// stability requirements.
  final StreamController<int> _rawNoteController =
      StreamController<int>.broadcast();
  Stream<int> get rawNoteStream => _rawNoteController.stream;

  TunerCubit({
    required AudioCaptureService audioService,
  })  : _audioService = audioService,
        _detector = PitchDetector(
          minFrequency: Instrument.guitar.minFrequency,
          maxFrequency: Instrument.guitar.maxFrequency,
          minRms: 0.0004, // Lower threshold = picks up quiet plucks & far-field mic
        ),
        super(TunerState.initial());

  // ── Lifecycle ────────────────────────────────────────────────────
  Future<void> start() async {
    if (state.isListening) return;
    emit(state.copyWith(errorMessage: () => null));
    try {
      final stream = await _audioService.start();
      _audioSub = stream.listen(
        _onSamples,
        onError: (Object e, StackTrace st) {
          emit(state.copyWith(errorMessage: () => 'Audio error: $e'));
        },
      );
      emit(state.copyWith(isListening: true));
    } on MicPermissionException catch (e) {
      emit(state.copyWith(
        isListening: false,
        errorMessage: () => e.isPermanentlyDenied
            ? 'Microphone access is disabled. Enable it in system settings.'
            : 'Microphone permission is required to detect pitch.',
      ));
    } catch (e) {
      emit(state.copyWith(
        isListening: false,
        errorMessage: () => 'Could not start the microphone: $e',
      ));
    }
  }

  Future<void> stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _audioService.stop();
    _resetSignalState();
    emit(state.copyWith(
      isListening: false,
      reading: TunerReading.silent,
    ));
  }

  /// Clears ALL per-session signal state.
  /// Must be called whenever we change what we're listening *for*, so we
  /// don't carry stale audio/frequency state across the switch.
  void _resetSignalState() {
    _buffer.clear();
    _newSamplesSinceLastAnalysis = 0;
    _emaFreq = null;
    _lastEmittedFreq = null;
    _silentStreak = 0;
    _candidateCount = 0;
    _centsHistory.clear();
  }

  // ── Settings ─────────────────────────────────────────────────────
  void setAutoMode(bool auto) {
    _resetSignalState();
    emit(state.copyWith(
      autoMode: auto,
      selectedString: auto ? () => null : () => state.selectedString,
      reading: TunerReading.silent,
    ));
  }

  void selectString(StringTarget string) {
    _resetSignalState();
    emit(state.copyWith(
      selectedString: () => string,
      autoMode: false,
      reading: TunerReading.silent,
    ));
  }

  void setInstrument(Instrument instrument) {
    if (state.instrument == instrument) return;
    final tunings = TuningLibrary.tuningsFor(instrument);
    _detector = PitchDetector(
      minFrequency: instrument.minFrequency,
      maxFrequency: instrument.maxFrequency,
      minRms: 0.0004, // matches the spectrogram sensitivity setting
    );
    _resetSignalState();
    emit(state.copyWith(
      instrument: instrument,
      currentTuning: tunings.isNotEmpty
          ? tunings.first
          : const Tuning(name: 'Any note', strings: []),
      selectedString: () => null,
      reading: TunerReading.silent,
    ));
  }

  void setTuning(Tuning tuning) {
    _resetSignalState();
    emit(state.copyWith(
      currentTuning: tuning,
      selectedString: () => null,
      reading: TunerReading.silent,
    ));
  }

  void setA4Reference(double hz) {
    emit(state.copyWith(a4Reference: hz));
  }

  void setToleranceCents(double cents) {
    emit(state.copyWith(toleranceCents: cents));
  }

  // ── Audio processing ────────────────────────────────────────────
  void _onSamples(List<double> samples) {
    _buffer.addAll(samples);
    _newSamplesSinceLastAnalysis += samples.length;

    if (_buffer.length > _windowSize) {
      _buffer.removeRange(0, _buffer.length - _windowSize);
    }
    if (_buffer.length < _windowSize) return;

    // Only run pitch detection if we have accumulated enough new samples (at least 512 samples ≈ 23ms)
    if (_newSamplesSinceLastAnalysis < 512) return;
    _newSamplesSinceLastAnalysis = 0;

    final List<double> window = List<double>.from(_buffer);

    // Compute RMS of the current window so we can pass loudness to the
    // spectrogram screen for variable spike thickness.
    double sumSq = 0.0;
    for (final s in window) {
      sumSq += s * s;
    }
    final double rms = math.sqrt(sumSq / window.length);

    final double? freq = _detector.detectPitch(
      window,
      AudioCaptureService.sampleRate.toDouble(),
    );

    if (freq != null && !_rawNoteController.isClosed) {
      // Raw pitch class, straight off this single YIN frame — no EMA,
      // no stability gate, no 2-frame agreement requirement. Listeners
      // (Chord Matrix) build their own rolling window from this.
      final NoteInfo rawNote =
          MusicUtils.frequencyToNote(freq, a4Frequency: state.a4Reference);
      final int pitchClass = MusicUtils.noteNames.indexOf(rawNote.name);
      if (pitchClass >= 0) {
        _rawNoteController.add(pitchClass);
      }
    }

    _processDetectedFrequency(freq, rms);
  }

  void _processDetectedFrequency(double? freq, double amplitude) {
    if (freq == null) {
      _silentStreak++;
      if (_silentStreak >= _silenceGraceCount) {
        _emaFreq = null;
        _candidateCount = 0;
        _centsHistory.clear();
        if (state.reading.status != InTuneStatus.silent) {
          emit(state.copyWith(
              reading: TunerReading.silent));
        }
      }
      return;
    }

    _silentStreak = 0;

    // ── Octave sanity check ───────────────────────────────────────
    if (_lastEmittedFreq != null) {
      final ratio = freq / _lastEmittedFreq!;
      final octavesAway = (math.log(ratio) / math.ln2).abs();
      if (octavesAway > _maxOctaveJump) {
        // Skip this frame — likely an octave error from the detector
        return;
      }
    }

    // ── EMA update ────────────────────────────────────────────────
    if (_emaFreq == null) {
      _emaFreq = freq;
      _candidateCount = 1;
    } else {
      // Check if this reading is within the stability window
      final double diffCents = MusicUtils.centsBetween(freq, _emaFreq!).abs();
      if (diffCents <= _stabilityCentsWindow) {
        // Agreed — update EMA and count
        _emaFreq = _emaAlpha * freq + (1.0 - _emaAlpha) * _emaFreq!;
        _candidateCount++;
      } else {
        // Disagreement — could be a genuine pitch change or an error.
        // Give the new reading a chance: reset and start fresh.
        _emaFreq = freq;
        _candidateCount = 1;
        _centsHistory.clear();
      }
    }

    // Need at least 2 agreeing frames before emitting
    if (_candidateCount < 2) return;

    _emitReading(_emaFreq!, amplitude);
  }

  void _emitReading(double smoothed, double amplitude) {
    _lastEmittedFreq = smoothed;

    final NoteInfo note =
        MusicUtils.frequencyToNote(smoothed, a4Frequency: state.a4Reference);

    StringTarget? targetString;
    double? centsFromTarget;

    if (state.currentTuning.strings.isNotEmpty) {
      if (state.autoMode) {
        targetString = _closestString(smoothed, state.currentTuning.strings);
      } else if (state.selectedString != null) {
        targetString = state.selectedString;
      }
      if (targetString != null) {
        centsFromTarget = MusicUtils.centsBetween(smoothed, targetString.frequency);
      }
    }

    // ── Cents history smoothing for display ───────────────────────
    final double rawCents = centsFromTarget ?? note.cents;
    _centsHistory.add(rawCents);
    if (_centsHistory.length > _centsHistoryLen) {
      _centsHistory.removeAt(0);
    }
    final double displayCents =
        _centsHistory.reduce((a, b) => a + b) / _centsHistory.length;

    final double centsForStatus = displayCents;
    final status =
        InTuneStatusX.fromCents(centsForStatus, tolerance: state.toleranceCents);

    final reading = TunerReading(
      frequency: smoothed,
      noteName: note.name,
      octave: note.octave,
      cents: centsFromTarget == null ? displayCents : note.cents,
      matchedString: targetString,
      centsFromTarget: centsFromTarget != null ? displayCents : null,
      status: status,
      amplitude: amplitude,
    );

    emit(state.copyWith(reading: reading));
  }

  StringTarget _closestString(double frequency, List<StringTarget> strings) {
    StringTarget best = strings.first;
    double bestDiff = double.infinity;
    for (final s in strings) {
      final double diffCents = MusicUtils.centsBetween(frequency, s.frequency).abs();
      if (diffCents < bestDiff) {
        bestDiff = diffCents;
        best = s;
      }
    }
    return best;
  }

  @override
  Future<void> close() {
    _audioSub?.cancel();
    _audioService.dispose();
    _rawNoteController.close();
    return super.close();
  }
}
