import 'dart:async';

import 'package:guitar_tuner_app/tuner/tuner_engine.dart';
import 'package:record/record.dart';

class RecorderPage {
  final _recorder = AudioRecorder();
  Stream<List<int>>? _stream;
  StreamSubscription<List<int>>? _streamSubscription;

  final _processor = GuitarPitchStreamProcessor(
      sampleRate: 44100,
      windowSize: 4096,
      hopSize: 1024,
      threshold: 0.10
  );

  bool _isListening = false;

  Future <void> _startListening() async {

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      print('Microphone permission denied');
      return;
    }

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

    _streamSubscription = _stream!.listen((data) {
      final result = _processor.addChunkAndDetect(data);
      if (result.isPitched) {
        print("------------------------------------------------");
        print("Probability :: ${result.probability}");
        print("FrequencyHz :: ${result.frequencyHz}");
        print("Pitched :: ${result.isPitched}");
        print("------------------------------------------------");
      }
    });
    _isListening = true;
  }

  Future <void> _stopListening() async {
    if (!_isListening) return;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    await _recorder.stop();
    _isListening = false;
  }

  void onToggleButtonPressed(){
    _isListening? _stopListening():_startListening();
  }
}