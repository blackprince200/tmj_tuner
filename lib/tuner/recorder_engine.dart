import 'dart:math';
import 'dart:typed_data';

import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

final AudioRecorder _recorder = AudioRecorder();
Stream<List<int>> ? _stream;
final List<int> bufferData = [];

final detector = PitchDetector(
  audioSampleRate: 44100,
  bufferSize: 4096
);

final _pitchDetectorDart = PitchDetector(
  audioSampleRate: 44100,
  bufferSize: 4096,
);



Future<void> startTuner() async {
  try {

    if(await _recorder.isRecording()){
      return;
    }

    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      throw Exception("Microphone Failed");
    }

    _stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        streamBufferSize: 1024,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false
      ),
    );


    final pcmBuffer = <int>[];

    await for (final chunk in _stream!) {
      pcmBuffer.addAll(chunk);

      // PCM16 = 2 bytes per sample.
      // 4096 samples = 8192 bytes.
      const requiredBytes = 4096 * 2;

      while (pcmBuffer.length >= requiredBytes) {
        final frame = Uint8List.fromList(
          pcmBuffer.sublist(0, requiredBytes),
        );

        pcmBuffer.removeRange(0, requiredBytes);

        final detectedPitch = await _pitchDetectorDart.getPitchFromIntBuffer(frame);

        if (!detectedPitch.pitched) {
          continue;
        }

        print('Frequency: ${detectedPitch.pitch} Hz');
      }
    }




    // _stream!.listen((data){
    //   final samples=pcm16ToSamples(data);
    //
    //   bufferData.addAll(samples);
    //
    //   if(bufferData.length>=4096){
    //     final windowData=Int16List.fromList(
    //       bufferData.sublist(0,4096)
    //     );
    //
    //     detect(windowData);
    //
    //     bufferData.removeRange(0, 2048);
    //   }
    // },
    //   onError: (error,stackTrace){
    //   throw Exception('error : $error \n''error at: $stackTrace');
    //   },
    //     cancelOnError: false
    // );
  } catch (e, st){
    throw Exception('error : $e \n''error at: $st');
  }
}


Future<void> stopTuner() async{
  try{

    final isRecording = await _recorder.isRecording();
    if(!isRecording){
      return;
    }

    await _recorder.stop();
  }catch(e,st){
    throw Exception('error : $e \n''error at: $st');
  }
}

Int16List pcm16ToSamples (List<int> data){
  final samples = Int16List(data.length~/2);

  for (int i =0,  j =0; i+1<data.length; i+=2, j++){
    int sample=data[i] | (data[i+1]<<8);

    if(sample>=0x8000){
      sample -=0x10000;
    }

    samples[j] = sample;
  }
  return samples;
}

Int16List removeDcOffset(Int16List samples){
  if(samples.isEmpty)return samples;

  int sum=0;

  for(final sample in samples){
    sum += sample;
  }

  final dcOffset = sum/samples.length;

  final  result = Int16List(samples.length);

  for (int i = 0; i < samples.length; i++) {
    final corrected = (samples[i] - dcOffset).round();

    result[i] = corrected.clamp(-32768, 32767);
  }

  return result;
}


// Future<void> detect(Int16List samples) async{
//
//   print(samples.length);
//
//   final bytes = samples.buffer.asUint8List(
//     samples.offsetInBytes,
//     samples.lengthInBytes,
//   );
//
//   final result = await detector.getPitchFromIntBuffer(bytes);
//
//   print(result);
// }




Future<void> detect(Int16List samples) async {
  int min = samples[0];
  int max = samples[0];

  double sumAbs = 0;
  double sumSquared = 0;

  for (final sample in samples) {
    if (sample < min) min = sample;
    if (sample > max) max = sample;

    sumAbs += sample.abs();
    sumSquared += sample * sample;
  }

  final averageAbs = sumAbs / samples.length;
  final rms = sqrt(sumSquared / samples.length);

  print('---------------------------');
  print('samples: ${samples.length}');
  print('min: $min');
  print('max: $max');
  print('avgAbs: $averageAbs');
  print('RMS: $rms');
  print('first 20: ${samples.take(20).toList()}');

  final bytes = samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  );

  final result = await detector.getPitchFromIntBuffer(bytes);

  print('pitch: ${result.pitch}');
}


