import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_app/core/wav_generator.dart';

void main() {
  group('WavGenerator', () {
    test('generates valid WAV file format headers and sizes', () {
      final double freq = 440.0;
      final int sampleRate = 22050;
      final double duration = 0.5; // 0.5 seconds
      
      final bytes = WavGenerator.generate(
        frequency: freq,
        waveType: WaveType.sine,
        sampleRate: sampleRate,
        duration: duration,
      );

      // Total expected samples: 22050 * 0.5 = 11025 samples
      // Data size: 11025 * 2 bytes = 22050 bytes
      // Total file size: 44 bytes header + 22050 bytes data = 22094 bytes
      expect(bytes.length, 22094);

      // Verify RIFF header
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      
      // Verify size in header (fileSize - 8 = 22086)
      final sizeData = ByteData.sublistView(Uint8List.fromList(bytes.sublist(4, 8)));
      expect(sizeData.getUint32(0, Endian.little), 22086);

      // Verify WAVE format
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');

      // Verify data sub-chunk
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');

      // Verify data size (22050)
      final dataSizeData = ByteData.sublistView(Uint8List.fromList(bytes.sublist(40, 44)));
      expect(dataSizeData.getUint32(0, Endian.little), 22050);
    });
  });
}
