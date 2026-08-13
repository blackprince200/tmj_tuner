import 'dart:async';

import 'package:guitar_tuner_app/services/audio_capture_service.dart';

/// A controllable fake [AudioCaptureService] for tests: instead of a
/// real microphone, the test pushes sample chunks directly via
/// [pushSamples], letting us simulate exact audio scenarios (e.g.
/// "user is playing E2, then immediately switches to playing A2")
/// deterministically and without any platform/hardware dependency.
class FakeAudioCaptureService implements AudioCaptureService {
  StreamController<List<double>>? _controller;
  bool _started = false;

  @override
  bool get isCapturing => _started;

  @override
  Future<Stream<List<double>>> start() async {
    _controller = StreamController<List<double>>.broadcast();
    _started = true;
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    await _controller?.close();
    _controller = null;
    _started = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  /// Pushes a chunk of samples into the active stream, simulating
  /// microphone input. Throws if [start] hasn't been called.
  void pushSamples(List<double> samples) {
    if (_controller == null || _controller!.isClosed) {
      throw StateError('FakeAudioCaptureService: not started');
    }
    _controller!.add(samples);
  }
}
