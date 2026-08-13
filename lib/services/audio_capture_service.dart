/// Wraps the `record` package to expose a simple, app-specific API:
/// a stream of normalized double samples (-1.0..1.0) ready to feed into
/// [PitchDetector], plus clean permission + lifecycle handling.
///
/// This sits in the Model layer (it's a data source, not UI and not
/// app state) and is injected into the ViewModel (TunerCubit) rather
/// than constructed inside it, so it can be replaced with a fake in
/// tests without touching any real microphone.
library audio_capture_service;

import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Thrown when the microphone permission is denied (including
/// permanently denied) so the ViewModel can show the right message
/// and, if needed, offer to send the user to app settings.
class MicPermissionException implements Exception {
  final bool isPermanentlyDenied;
  MicPermissionException({required this.isPermanentlyDenied});

  @override
  String toString() => 'MicPermissionException(permanentlyDenied: $isPermanentlyDenied)';
}

abstract class AudioCaptureService {
  /// Sample rate we request from the platform. 22050Hz is plenty for
  /// guitar/bass/ukulele fundamentals (well under Nyquist for our
  /// highest frequency of interest) and keeps CPU usage low for
  /// real-time processing on lower-end devices.
  static const int sampleRate = 22050;
  static const int channels = 1;

  bool get isCapturing;

  /// Checks/requests mic permission, then starts streaming normalized
  /// audio samples. Throws [MicPermissionException] if permission isn't
  /// granted.
  Future<Stream<List<double>>> start();

  Future<void> stop();

  Future<void> dispose();
}

class RecordAudioCaptureService implements AudioCaptureService {
  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _subscription;
  StreamController<List<double>>? _samplesController;

  RecordAudioCaptureService({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  @override
  bool get isCapturing => _samplesController != null;

  @override
  Future<Stream<List<double>>> start() async {
    await _ensurePermission();

    // If a previous session wasn't torn down cleanly, close it before
    // opening a new one rather than leaking the old controller/stream.
    await stop();

    final controller = StreamController<List<double>>.broadcast();
    _samplesController = controller;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AudioCaptureService.sampleRate,
        numChannels: AudioCaptureService.channels,
        // Let the OS apply its own gain/noise handling where available
        // — but here we deliberately disable that, since phone mics
        // are tuned for voice, not instrument pickup ranges, and these
        // "helpful" filters can attenuate the very signal we want.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _subscription = stream.listen(
      (Uint8List bytes) {
        final samples = _pcm16BytesToDoubles(bytes);
        if (!controller.isClosed) controller.add(samples);
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      },
    );

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _samplesController?.close();
    _samplesController = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped — safe to ignore.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }

  Future<void> _ensurePermission() async {
    final status = await Permission.microphone.status;

    if (status.isGranted) return;

    if (status.isPermanentlyDenied) {
      throw MicPermissionException(isPermanentlyDenied: true);
    }

    final result = await Permission.microphone.request();
    if (!result.isGranted) {
      throw MicPermissionException(isPermanentlyDenied: result.isPermanentlyDenied);
    }
  }

  /// Converts little-endian 16-bit PCM bytes into normalized doubles.
  List<double> _pcm16BytesToDoubles(Uint8List bytes) {
    final int sampleCount = bytes.length ~/ 2;
    final Float64List out = Float64List(sampleCount);
    final ByteData byteData = ByteData.sublistView(bytes);
    for (int i = 0; i < sampleCount; i++) {
      final int sample = byteData.getInt16(i * 2, Endian.little);
      out[i] = sample / 32768.0;
    }
    return out;
  }
}
