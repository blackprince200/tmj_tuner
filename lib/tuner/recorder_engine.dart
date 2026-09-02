import 'package:record/record.dart';

final AudioRecorder _recorder = AudioRecorder();

Future<void> startTuner() async {
  try {
    final hasPermission = await _recorder.hasPermission();

    print('Permission: $hasPermission');

    if (!hasPermission) {
      print('Microphone permission denied');
      return;
    }

    print('Starting recorder...');

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ),
    );

    print('Stream started');

    stream.listen(
          (audioData) {
        final nonZero =
            audioData.where((byte) => byte != 0).length;

        print(
          'Length: ${audioData.length}, '
              'Non-zero: $nonZero',
        );
      },
      onError: (error) {
        print('STREAM ERROR: $error');
      },
      onDone: () {
        print('STREAM DONE');
      },
    );
  } catch (e, st) {
    print('RECORDER ERROR: $e');
    print(st);
  }
}
