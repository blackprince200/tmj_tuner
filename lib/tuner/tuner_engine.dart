// YIN Pitch Detection Algorithm
// startStream() PCM16 output.
// --------------------------------------------------


import 'dart:math';
import 'dart:typed_data';

class PitchResult {
  final double frequencyHz;
  final double probability; // confidence 0.0–1.0
  final bool isPitched;

  PitchResult(this.frequencyHz, this.probability, this.isPitched);
  static final PitchResult none = PitchResult(0.0, 0.0, false);
}

class YinPitchDetector {
  final int sampleRate;
  final int bufferSize;   // total samples analyzed per detection pass
  final double threshold; // CMNDF threshold — lower = more sensitive
  final double minFrequencyHz;
  final double maxFrequencyHz;

  late final int _minTau;
  late final int _maxTau;
  late final Float64List _diff;
  late final Float64List _cmnd;

  YinPitchDetector({
    this.sampleRate = 44100,
    this.bufferSize = 4096,
    this.threshold = 0.10,
    this.minFrequencyHz = 70.0,
    this.maxFrequencyHz = 1200.0,
  }) {
    _maxTau = (sampleRate / minFrequencyHz).ceil();
    _minTau = (sampleRate / maxFrequencyHz).floor().clamp(1, bufferSize - 1);

    if (_maxTau >= bufferSize) {
      throw ArgumentError(
        'bufferSize ($bufferSize) too small for minFrequencyHz '
            '($minFrequencyHz Hz) at sampleRate ($sampleRate). '
            'Need bufferSize > $_maxTau.',
      );
    }

    _diff = Float64List(_maxTau + 1);
    _cmnd = Float64List(_maxTau + 1);
  }

  /// samples: normalized floats in [-1, 1], length >= bufferSize
  PitchResult detectPitch(Float32List samples) {
    if (samples.length < bufferSize) return PitchResult.none;

    _computeDifference(samples);
    _computeCMND();

    final int tauEstimate = _absoluteThreshold();
    if (tauEstimate == -1) return PitchResult.none;

    final double betterTau = _parabolicInterpolation(tauEstimate);
    if (betterTau <= 0) return PitchResult.none;

    final double frequency = sampleRate / betterTau;
    final double confidence = (1.0 - _cmnd[tauEstimate]).clamp(0.0, 1.0);

    if (frequency < minFrequencyHz * 0.9 || frequency > maxFrequencyHz * 1.1) {
      return PitchResult.none;
    }

    return PitchResult(frequency, confidence, true);
  }

  void _computeDifference(Float32List x) {
    _diff[0] = 0.0;
    final int w = bufferSize - _maxTau;
    for (int tau = 1; tau <= _maxTau; tau++) {
      double sum = 0.0;
      for (int j = 0; j < w; j++) {
        final double delta = x[j] - x[j + tau];
        sum += delta * delta;
      }
      _diff[tau] = sum;
    }
  }

  void _computeCMND() {
    _cmnd[0] = 1.0;
    double runningSum = 0.0;
    for (int tau = 1; tau <= _maxTau; tau++) {
      runningSum += _diff[tau];
      _cmnd[tau] = (runningSum == 0.0) ? 1.0 : _diff[tau] * tau / runningSum;
    }
  }

  int _absoluteThreshold() {
    for (int tau = _minTau; tau <= _maxTau; tau++) {
      if (_cmnd[tau] < threshold) {
        while (tau + 1 <= _maxTau && _cmnd[tau + 1] < _cmnd[tau]) {
          tau++;
        }
        return tau;
      }
    }
    return -1;
  }

  double _parabolicInterpolation(int tauEstimate) {
    final int x0 = (tauEstimate < 1) ? tauEstimate : tauEstimate - 1;
    final int x2 = (tauEstimate + 1 < _maxTau + 1) ? tauEstimate + 1 : tauEstimate;

    if (x0 == tauEstimate) {
      return _cmnd[tauEstimate] <= _cmnd[x2] ? tauEstimate.toDouble() : x2.toDouble();
    }
    if (x2 == tauEstimate) {
      return _cmnd[tauEstimate] <= _cmnd[x0] ? tauEstimate.toDouble() : x0.toDouble();
    }

    final double s0 = _cmnd[x0];
    final double s1 = _cmnd[tauEstimate];
    final double s2 = _cmnd[x2];
    final double denom = 2 * s1 - s2 - s0;
    if (denom == 0.0) return tauEstimate.toDouble();

    return tauEstimate + (s2 - s0) / (2 * denom);
  }
}


// Buffering helper for `record` package's raw PCM16 stream.
class GuitarPitchStreamProcessor {
  final YinPitchDetector _yin;
  final int windowSize;
  final int hopSize;

  final List<int> _rollingBuffer = [];
  int _samplesSinceLastDetect = 0;

  GuitarPitchStreamProcessor({
    int sampleRate = 44100,
    this.windowSize = 4096,
    this.hopSize = 1024,
    double threshold = 0.10,
  }) : _yin = YinPitchDetector(
    sampleRate: sampleRate,
    bufferSize: windowSize,
    threshold: threshold,
  );

  PitchResult addChunkAndDetect(List<int> pcm16Bytes) {
    // Convert raw little-endian PCM16 bytes -> Int16 samples
    final byteData = Uint8List.fromList(pcm16Bytes).buffer.asByteData();
    for (int i = 0; i + 1 < pcm16Bytes.length; i += 2) {
      final int sample = byteData.getInt16(i, Endian.little);
      _rollingBuffer.add(sample);
    }

    // Keep only the most recent `windowSize` samples
    while (_rollingBuffer.length > windowSize) {
      _rollingBuffer.removeAt(0);
    }

    _samplesSinceLastDetect += pcm16Bytes.length ~/ 2;

    // Only run YIN once we have a full window AND enough new data
    if (_rollingBuffer.length < windowSize || _samplesSinceLastDetect < hopSize) {
      return PitchResult.none;
    }
    _samplesSinceLastDetect = 0;

    // Convert int16 -> normalized float32 for YIN
    final Float32List floatSamples = Float32List(windowSize);
    for (int i = 0; i < windowSize; i++) {
      floatSamples[i] = _rollingBuffer[i] / 32768.0;
    }

    return _yin.detectPitch(floatSamples);
  }
}
