import 'dart:math';
import 'dart:typed_data';

import 'package:record/record.dart';

final AudioRecorder _recorder = AudioRecorder();

Stream<List<int>>? _stream;

bool _isRunning = false;

// START TUNER
Future<void> startTuner() async {
  if (_isRunning) return;

  try {
    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    _isRunning = true;

    _stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        streamBufferSize: 1024,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    final pcmBuffer = <int>[];

    const sampleRate = 44100;
    const frameSamples = 4096;
    const frameBytes = frameSamples * 2; // PCM16 = 2 bytes/sample

    await for (final chunk in _stream!) {
      if (!_isRunning) break;

      pcmBuffer.addAll(chunk);

      while (pcmBuffer.length >= frameBytes) {


        // Get exactly 4096 PCM16 sample
        final bytes = Uint8List.fromList(
          pcmBuffer.sublist(0, frameBytes),
        );

        pcmBuffer.removeRange(0, frameBytes);



        // PCM16 bytes -> Int16 samples
        final samples = pcm16ToSamples(bytes);



        // Debug information
        final stats = calculateAudioStats(samples);

        print('----------------------------');
        print('SAMPLES: ${samples.length}');
        print('MIN: ${stats.min}');
        print('MAX: ${stats.max}');
        print('RMS: ${stats.rms.toStringAsFixed(2)}');


        // Pitch detection
        final pitch = detectPitchAutocorrelation(
          samples,
          sampleRate,
        );

        if (pitch > 0) {
          print(
            'PITCH: ${pitch.toStringAsFixed(2)} Hz',
          );
        } else {
          print('NO PITCH');
        }
      }
    }
  } catch (e, st) {
    print('Tuner error: $e');
    print(st);
  } finally {
    _isRunning = false;
  }
}

//STOP TUNER

Future<void> stopTuner() async {
  try {
    _isRunning = false;

    final isRecording = await _recorder.isRecording();

    if (isRecording) {
      await _recorder.stop();
    }

    _stream = null;
  } catch (e, st) {
    print('Stop tuner error: $e');
    print(st);
  }
}

//PCM16 LITTLE-ENDIAN -> Int16List

Int16List pcm16ToSamples(List<int> data) {
  final sampleCount = data.length ~/ 2;

  final samples = Int16List(sampleCount);

  for (int i = 0; i < sampleCount; i++) {
    final byteIndex = i * 2;

    int value =
    (data[byteIndex] & 0xFF) |
    ((data[byteIndex + 1] & 0xFF) << 8);

    // Convert unsigned 16-bit -> signed 16-bit
    if (value >= 0x8000) {
      value -= 0x10000;
    }

    samples[i] = value;
  }

  return samples;
}

//AUDIO STATISTICS

class AudioStats {
  final int min;
  final int max;
  final double rms;

  AudioStats({
    required this.min,
    required this.max,
    required this.rms,
  });
}

AudioStats calculateAudioStats(Int16List samples) {
  if (samples.isEmpty) {
    return AudioStats(
      min: 0,
      max: 0,
      rms: 0,
    );
  }

  int min = samples[0];
  int max = samples[0];

  double sumSquared = 0;

  for (final sample in samples) {
    if (sample < min) {
      min = sample;
    }

    if (sample > max) {
      max = sample;
    }

    sumSquared += sample * sample;
  }

  final rms = sqrt(
    sumSquared / samples.length,
  );

  return AudioStats(
    min: min,
    max: max,
    rms: rms,
  );
}

// AUTOCORRELATION PITCH DETECTOR

double detectPitchAutocorrelation(
    Int16List samples,
    int sampleRate,
    ) {
  if (samples.length < 2048) {
    return -1;
  }

  //Calculate DC offset and RMS

  double sum = 0;
  double sumSquared = 0;

  for (final sample in samples) {
    sum += sample;
    sumSquared += sample * sample;
  }

  final mean = sum / samples.length;

  final rms = sqrt(
    sumSquared / samples.length,
  );

  //Ignore very quiet input

  if (rms < 300) {
    return -1;
  }

  // Expected pitch range

  const minFrequency = 60.0;
  const maxFrequency = 500.0;

  final minLag =
  (sampleRate / maxFrequency).round();

  final maxLag =
  (sampleRate / minFrequency).round();


  // Find strongest autocorrelation peak
  int bestLag = -1;
  double bestCorrelation = 0;

  for (
  int lag = minLag;
  lag <= maxLag;
  lag++
  ) {
    final count = samples.length - lag;

    if (count <= 0) {
      continue;
    }

    double correlation = 0;
    double energy1 = 0;
    double energy2 = 0;

    for (int i = 0; i < count; i++) {
      final x = samples[i] - mean;
      final y = samples[i + lag] - mean;

      correlation += x * y;
      energy1 += x * x;
      energy2 += y * y;
    }

    if (energy1 <= 0 || energy2 <= 0) {
      continue;
    }

    final normalized =
        correlation / sqrt(energy1 * energy2);

    if (normalized > bestCorrelation) {
      bestCorrelation = normalized;
      bestLag = lag;
    }
  }

  //No reliable pitch

  if (bestLag <= 0) {
    return -1;
  }

  // Confidence check
  if (bestCorrelation < 0.5) {
    return -1;
  }


  // Convert lag -> frequency
  final frequency =
      sampleRate / bestLag;


  // Final range check

  if (frequency < minFrequency ||
      frequency > maxFrequency) {
    return -1;
  }

  return frequency;
}
