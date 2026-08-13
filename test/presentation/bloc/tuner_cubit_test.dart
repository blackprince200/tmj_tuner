import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_app/data/models/detected_pitch.dart';
import 'package:guitar_tuner_app/data/models/tuning.dart';
import 'package:guitar_tuner_app/presentation/bloc/tuner_cubit.dart';

import '../../fakes/fake_audio_capture_service.dart';

/// Generates a pure sine wave starting at sample offset [startIndex] —
/// callers feeding multiple sequential chunks of the SAME note must
/// pass increasing offsets so the chunks splice into one continuous
/// waveform. Restarting phase at 0 for every chunk (as a naive
/// per-call generator would) creates an artificial discontinuity at
/// each chunk boundary, which injects broadband noise into the
/// analysis window and can itself prevent the pitch detector from
/// locking on — that would be a bug in the *test*, not the app, so we
/// guard against it explicitly here.
List<double> sineWave(double freq, double sampleRate, int count, {double amp = 0.5, int startIndex = 0}) {
  return List<double>.generate(
    count,
    (i) => amp * math.sin(2 * math.pi * freq * (startIndex + i) / sampleRate),
  );
}

/// Pushes enough chunks of [freq] to satisfy both the analysis window
/// (TunerCubit._windowSize, 8192 samples) AND the stability gate
/// (TunerCubit._stabilityRequired, 2 agreeing detections) — i.e.
/// enough for a steady, sustained note to actually produce a reading.
/// Mirrors how a real instrument note arrives as many small streaming
/// chunks rather than one giant block; phase is kept continuous across
/// chunks (see [sineWave]'s doc) so this behaves like real audio.
Future<void> feedSustainedNote(
  FakeAudioCaptureService audio,
  double freq,
  double sampleRate,
  int windowSize,
) async {
  var sampleIndex = 0;

  audio.pushSamples(sineWave(freq, sampleRate, windowSize, startIndex: sampleIndex));
  sampleIndex += windowSize;
  await Future<void>.delayed(Duration.zero);

  for (var i = 0; i < 3; i++) {
    audio.pushSamples(sineWave(freq, sampleRate, 512, startIndex: sampleIndex));
    sampleIndex += 512;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const sampleRate = 22050.0;
  const windowSize = 8192;

  late FakeAudioCaptureService audio;
  late TunerCubit cubit;

  setUp(() {
    audio = FakeAudioCaptureService();
    cubit = TunerCubit(audioService: audio);
  });

  tearDown(() async {
    await cubit.close();
  });

  group('Regression: switching strings must not echo the previous reading', () {
    test(
      'selecting a different string immediately clears the reading, and stale '
      'audio left in the buffer does NOT re-trigger the old note '
      '(this is the exact "same string is not coming" bug from the original app)',
      () async {
        await cubit.start();

        // Feed a sustained E2 (82.41Hz) note — enough for the detector
        // to lock on and emit a reading matched to the low E string.
        await feedSustainedNote(audio, 82.41, sampleRate, windowSize);

        expect(cubit.state.reading.matchedString?.label, 'E2',
            reason: 'Sanity check: detector should be locked onto E2 before we switch strings');

        // User taps a different string in the UI (A2) — this is
        // exactly the action that triggered the bug.
        final a2 = const StringTarget(label: 'A2', frequency: 110.00);
        cubit.selectString(a2);

        // Immediately after switching, the reading must already be
        // reset to silent — not still showing E2's old data.
        expect(cubit.state.reading.status, InTuneStatus.silent,
            reason: 'Reading must reset to silent the instant the string selection changes');
        expect(cubit.state.selectedString, a2);

        // THE KEY REGRESSION CHECK: push a SMALL chunk (smaller than
        // the analysis window) of the OLD E2 frequency, simulating
        // audio that was already "in flight" in the stream pipeline
        // at the moment the user tapped a new string.
        //
        // If `_buffer` were NOT cleared by selectString (the original
        // bug), it would still contain a full ~8192-sample window of
        // E2 audio from before the switch, so this tiny new chunk
        // would arrive on top of an already-full buffer and
        // IMMEDIATELY re-detect and re-emit E2 — exactly the "stuck
        // on the old string" symptom that was reported.
        //
        // With the fix (_resetSignalState clears _buffer too), the
        // buffer is empty after selectString, so this small chunk is
        // nowhere near enough to fill the analysis window again —
        // _onSamples must return early and emit nothing.
        audio.pushSamples(sineWave(82.41, sampleRate, 200));
        await Future<void>.delayed(Duration.zero);

        expect(
          cubit.state.reading.status,
          InTuneStatus.silent,
          reason: 'A small leftover chunk of the OLD frequency must not be enough to '
              'produce a reading — if it does, the buffer was not cleared on string switch',
        );
        expect(
          cubit.state.reading.matchedString,
          isNull,
          reason: 'Must not still be matched to the old E2 string after switching to A2',
        );

        // Now feed a sustained NEW target frequency (A2, 110Hz) and
        // confirm the cubit correctly reports A2 — proving the
        // pipeline is genuinely listening to fresh input, not just
        // failing to report anything at all. We start this from a
        // fresh buffer (the 200-sample leftover chunk above was far
        // too small to fill the window, so it's still sitting there,
        // but that's fine — a few real samples of A2 will dominate
        // the window almost immediately as more arrive).
        await feedSustainedNote(audio, 110.00, sampleRate, windowSize);

        expect(cubit.state.reading.matchedString?.label, 'A2',
            reason: 'After feeding genuinely new A2 audio, the cubit must report A2, not E2');
      },
    );

    test('switching instrument also clears stale buffer state', () async {
      await cubit.start();

      await feedSustainedNote(audio, 82.41, sampleRate, windowSize); // guitar E2
      expect(cubit.state.reading.status, isNot(InTuneStatus.silent));

      cubit.setInstrument(Instrument.bass);

      expect(cubit.state.reading.status, InTuneStatus.silent);
      expect(cubit.state.instrument, Instrument.bass);

      // Leftover small chunk of the old guitar-range frequency must
      // not resurrect a reading after the instrument switch.
      audio.pushSamples(sineWave(82.41, sampleRate, 200));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.reading.status, InTuneStatus.silent);
    });

    test('toggling auto mode off and back on clears stale buffer state', () async {
      await cubit.start();

      await feedSustainedNote(audio, 82.41, sampleRate, windowSize);
      expect(cubit.state.reading.status, isNot(InTuneStatus.silent));

      cubit.setAutoMode(false);
      expect(cubit.state.reading.status, InTuneStatus.silent);

      audio.pushSamples(sineWave(82.41, sampleRate, 200));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.reading.status, InTuneStatus.silent);
    });

    test('changing tuning clears stale buffer state', () async {
      await cubit.start();

      await feedSustainedNote(audio, 82.41, sampleRate, windowSize);
      expect(cubit.state.reading.status, isNot(InTuneStatus.silent));

      final dropD = TuningLibrary.tuningsFor(Instrument.guitar)
          .firstWhere((t) => t.name == 'Drop D');
      cubit.setTuning(dropD);

      expect(cubit.state.reading.status, InTuneStatus.silent);

      audio.pushSamples(sineWave(82.41, sampleRate, 200));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.reading.status, InTuneStatus.silent);
    });
  });

  group('Basic Cubit lifecycle', () {
    test('initial state is silent and not listening', () {
      expect(cubit.state.isListening, isFalse);
      expect(cubit.state.reading.status, InTuneStatus.silent);
    });

    test('start() sets isListening to true', () async {
      await cubit.start();
      expect(cubit.state.isListening, isTrue);
    });

    test('stop() resets to silent and not listening', () async {
      await cubit.start();
      await feedSustainedNote(audio, 82.41, sampleRate, windowSize);

      await cubit.stop();

      expect(cubit.state.isListening, isFalse);
      expect(cubit.state.reading.status, InTuneStatus.silent);
    });

    test('auto mode correctly matches the closest string', () async {
      await cubit.start();
      await feedSustainedNote(audio, 196.00, sampleRate, windowSize); // G3

      expect(cubit.state.autoMode, isTrue);
      expect(cubit.state.reading.matchedString?.label, 'G3');
    });
  });

  group('rawNoteStream (Chord Matrix support)', () {
    test(
      'emits a pitch class on the VERY FIRST detected frame, without '
      'waiting for the tuner\'s 2-frame stability gate — this is what '
      'the Chord Matrix screen depends on, since a strum/arpeggio moves '
      'through several different pitch classes faster than the gate '
      '(which resets its agreement counter on every note change) ever '
      'lets `state.reading` settle',
      () async {
        await cubit.start();

        final events = <int>[];
        final sub = cubit.rawNoteStream.listen(events.add);

        // A single full window of a sustained E2 (82.41Hz) is enough
        // for ONE YIN detection — unlike feedSustainedNote, we are not
        // trying to satisfy the stability gate here, just confirming
        // the raw stream doesn't require it.
        audio.pushSamples(sineWave(82.41, sampleRate, windowSize));
        await Future<void>.delayed(Duration.zero);

        expect(events, isNotEmpty,
            reason: 'rawNoteStream must emit immediately on first detection, '
                'not require 2 agreeing frames like state.reading does');
        // E2 = pitch class 4 (E), per MusicUtils.noteNames index.
        expect(events.first, 4);

        await sub.cancel();
      },
    );

    test(
      'emits a DIFFERENT pitch class for each note even when notes '
      'change every frame (simulating a fast strum/arpeggio) — proving '
      'this stream is independent of the tuner\'s stability/EMA gate, '
      'which would otherwise reset and suppress rapid note changes',
      () async {
        await cubit.start();

        final events = <int>[];
        final sub = cubit.rawNoteStream.listen(events.add);

        // C major triad notes: C4 (261.63Hz), E4 (329.63Hz), G4 (392.00Hz)
        var sampleIndex = 0;
        for (final freq in [261.63, 329.63, 392.00]) {
          audio.pushSamples(
              sineWave(freq, sampleRate, windowSize, startIndex: sampleIndex));
          sampleIndex += windowSize;
          await Future<void>.delayed(Duration.zero);
        }

        expect(events.length, 3,
            reason: 'Each of the 3 distinct notes should produce its own '
                'raw emission, with no gating between them');
        expect(events.toSet(), {0, 4, 7},
            reason: 'C=0, E=4, G=7 — the three pitch classes of a C major '
                'triad, exactly what ChordDetector needs to recognize the '
                'chord');

        await sub.cancel();
      },
    );
  });
}
