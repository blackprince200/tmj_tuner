import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum WaveType { sine, triangle, sawtooth, square }

class WavGenerator {
  WavGenerator._();

  /// Generates a mono 16-bit PCM WAV byte buffer for the given frequency, wave type,
  /// sample rate, and duration.
  static Uint8List generate({
    required double frequency,
    required WaveType waveType,
    int sampleRate = 22050,
    double duration = 1.5,
  }) {
    final int numSamples = (sampleRate * duration).round();
    final int dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final int fileSize = 36 + dataSize; // RIFF + format chunk + data header + data size

    final BytesBuilder builder = BytesBuilder();

    // ── RIFF Header ──────────────────────────────────────────────────
    builder.add(utf8.encode('RIFF'));
    builder.addByte(fileSize & 0xFF);
    builder.addByte((fileSize >> 8) & 0xFF);
    builder.addByte((fileSize >> 16) & 0xFF);
    builder.addByte((fileSize >> 24) & 0xFF);
    builder.add(utf8.encode('WAVE'));

    // ── Format Sub-chunk ─────────────────────────────────────────────
    builder.add(utf8.encode('fmt '));
    builder.addByte(16); // Chunk size (16 for PCM)
    builder.addByte(0);
    builder.addByte(0);
    builder.addByte(0);

    builder.addByte(1); // Audio format (1 = PCM)
    builder.addByte(0);

    builder.addByte(1); // Number of channels (1 = mono)
    builder.addByte(0);

    // Sample rate
    builder.addByte(sampleRate & 0xFF);
    builder.addByte((sampleRate >> 8) & 0xFF);
    builder.addByte((sampleRate >> 16) & 0xFF);
    builder.addByte((sampleRate >> 24) & 0xFF);

    // Byte rate (sampleRate * channels * bytesPerSample)
    final int byteRate = sampleRate * 2;
    builder.addByte(byteRate & 0xFF);
    builder.addByte((byteRate >> 8) & 0xFF);
    builder.addByte((byteRate >> 16) & 0xFF);
    builder.addByte((byteRate >> 24) & 0xFF);

    // Block align (channels * bytesPerSample = 2)
    builder.addByte(2);
    builder.addByte(0);

    // Bits per sample (16)
    builder.addByte(16);
    builder.addByte(0);

    // ── Data Sub-chunk ───────────────────────────────────────────────
    builder.add(utf8.encode('data'));
    builder.addByte(dataSize & 0xFF);
    builder.addByte((dataSize >> 8) & 0xFF);
    builder.addByte((dataSize >> 16) & 0xFF);
    builder.addByte((dataSize >> 24) & 0xFF);

    // ── Generate Waveform Samples ─────────────────────────────────────
    final double angularFreq = 2 * math.pi * frequency;
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double sampleVal = 0.0;

      switch (waveType) {
        case WaveType.sine:
          sampleVal = math.sin(angularFreq * t);
          break;
        case WaveType.triangle:
          final double period = 1.0 / frequency;
          final double phase = (t % period) / period; // Range: 0..1
          if (phase < 0.25) {
            sampleVal = phase * 4.0;
          } else if (phase < 0.75) {
            sampleVal = 2.0 - phase * 4.0;
          } else {
            sampleVal = phase * 4.0 - 4.0;
          }
          break;
        case WaveType.sawtooth:
          final double period = 1.0 / frequency;
          final double phase = (t % period) / period; // Range: 0..1
          sampleVal = 2.0 * phase - 1.0;
          break;
        case WaveType.square:
          final double period = 1.0 / frequency;
          final double phase = (t % period) / period; // Range: 0..1
          sampleVal = phase < 0.5 ? 1.0 : -1.0;
          break;
      }

      // Convert double [-1.0..1.0] to signed 16-bit integer [-32768..32767]
      final int intVal = (sampleVal * 32767.0).round().clamp(-32768, 32767);
      builder.addByte(intVal & 0xFF);
      builder.addByte((intVal >> 8) & 0xFF);
    }

    return builder.toBytes();
  }
}
