import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/music_utils.dart';
import '../../core/wav_generator.dart';
import '../../data/models/detected_pitch.dart';
import '../../data/models/tuning.dart';
import '../bloc/tuner_cubit.dart';
import '../bloc/tuner_state.dart';
import '../widgets/app_drawer.dart';
import '../widgets/instrument_settings_sheet.dart';

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with TickerProviderStateMixin {
  late AnimationController _vibrationCtrl;

  TunerCubit? _cubit;

  // Tone Generator State
  bool _toneExpanded = false;
  int? _playingMidi;
  WaveType _selectedWave = WaveType.sine;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _wasListeningBeforeTone = false;

  // Track last seen MIDI pitch to prevent note tape jumpiness during silence
  double _lastMidi = 40.0; // MIDI 40 = E2 (low guitar string)

  // Vertical keyboard notes: descending from C6 (84) down to C2 (36)
  final List<int> _keyboardNotes = List.generate(49, (i) => 84 - i);

  @override
  void initState() {
    super.initState();
    _vibrationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit = context.read<TunerCubit>();
  }

  @override
  void dispose() {
    _vibrationCtrl.dispose();
    _audioPlayer.dispose();
    _cubit?.stop();
    super.dispose();
  }

  Color _statusColor(InTuneStatus status) {
    switch (status) {
      case InTuneStatus.inTune:
        return const Color(0xFF00E676);
      case InTuneStatus.tooLow:
      case InTuneStatus.tooHigh:
        return const Color(0xFFFF4B6E);
      case InTuneStatus.silent:
        return const Color(0xFF4A4A6A);
    }
  }

  String _getNoteName(int midi) {
    final int index = midi % 12;
    final int octave = (midi ~/ 12) - 1;
    const names = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'];
    return '${names[index]}$octave';
  }

  // Generate and play audio tone
  Future<void> _playTone(int midi) async {
    final double frequency = MusicUtils.midiToFrequency(
      midi,
      a4Frequency: _cubit?.state.a4Reference ?? 440.0,
    );

    final bytes = WavGenerator.generate(
      frequency: frequency,
      waveType: _selectedWave,
      sampleRate: 22050,
      duration: 1.5,
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/tone_gen_$midi.wav');
      await file.writeAsBytes(bytes);

      if (_cubit?.state.isListening ?? false) {
        await _cubit?.stop();
        _wasListeningBeforeTone = true;
      }

      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(DeviceFileSource(file.path));

      setState(() {
        _playingMidi = midi;
      });
    } catch (e) {
      debugPrint('Error playing tone: $e');
    }
  }

  // Stop playing audio tone
  Future<void> _stopTone() async {
    try {
      await _audioPlayer.stop();

      if (_wasListeningBeforeTone) {
        await _cubit?.start();
        _wasListeningBeforeTone = false;
      }

      setState(() {
        _playingMidi = null;
      });
    } catch (e) {
      debugPrint('Error stopping tone: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      drawer: const AppDrawer(current: AppScreen.tuner),
      body: SafeArea(
        child: BlocBuilder<TunerCubit, TunerState>(
          builder: (context, state) {
            if (state.errorMessage != null) {
              return _buildError(context, state.errorMessage!);
            }
            return Column(
              children: [
                // Top header bar
                _buildTopBar(context, state),

                // Main Tuner Area (Tuning wheel, note tape)
                Expanded(
                  child: _buildTunerArea(state),
                ),

                // Collapsible Tone Generator Area
                _buildToneGenerator(state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B6E).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_off, size: 48, color: Color(0xFFFF4B6E)),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => _cubit?.start(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, TunerState state) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Tuner',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // Auto / Manual mode toggles
          GestureDetector(
            onTap: () => _cubit?.setAutoMode(!state.autoMode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: state.autoMode
                    ? const Color(0xFF00E676).withOpacity(0.15)
                    : const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: state.autoMode ? const Color(0xFF00E676) : Colors.white10,
                ),
              ),
              child: Text(
                'AUTO',
                style: TextStyle(
                  color: state.autoMode ? const Color(0xFF00E676) : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Settings bottom sheet toggle
          IconButton(
            onPressed: () => InstrumentSettingsSheet.show(context),
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF6B6B9A)),
          ),
          const SizedBox(width: 4),
          // Live Mic state toggle
          IconButton(
            onPressed: () async {
              if (state.isListening) {
                await _cubit?.stop();
              } else {
                await _cubit?.start();
              }
            },
            icon: Icon(
              state.isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: state.isListening ? const Color(0xFF00E676) : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTunerArea(TunerState state) {
    final reading = state.reading;
    final accentColor = _statusColor(reading.status);

    double? currentMidi;
    if (reading.frequency != null && reading.frequency! > 0) {
      currentMidi = 69 + 12 * (math.log(reading.frequency! / state.a4Reference) / math.ln2);
      _lastMidi = currentMidi;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Left: scrolling note tape
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 72,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
                  color: Color(0xFF090912),
                ),
                child: AnimatedBuilder(
                  animation: _vibrationCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: VerticalNoteTapePainter(
                        currentMidi: currentMidi,
                        lastMidi: _lastMidi,
                        accentColor: accentColor,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Center & Right: Vibrating String Circle layout
            Positioned(
              left: 72,
              right: 0,
              top: 0,
              bottom: 0,
              child: Stack(
                children: [
                  // Semicircle/Vibrating strings painter
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _vibrationCtrl,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: VibratingStringCirclePainter(
                            strings: state.currentTuning.strings,
                            currentFrequency: reading.frequency,
                            accentColor: accentColor,
                            vibrationTime: _vibrationCtrl.value * 2 * math.pi,
                            toleranceCents: state.toleranceCents,
                          ),
                        );
                      },
                    ),
                  ),

                  // "TUNE UP" / "TUNE DOWN" text overlays
                  Positioned(
                    top: 16,
                    left: 20,
                    child: Text(
                      'TUNE UP',
                      style: TextStyle(
                        color: const Color(0xFFFF4B6E).withOpacity(0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 20,
                    child: Text(
                      'TUNE DOWN',
                      style: TextStyle(
                        color: const Color(0xFFFF4B6E).withOpacity(0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                  // Top-left: frequency value
                  Positioned(
                    top: 40,
                    left: 20,
                    child: Text(
                      reading.frequency != null
                          ? '${reading.frequency!.toStringAsFixed(1)} Hz'
                          : '-- Hz',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Bottom-left: cents value
                  Positioned(
                    bottom: 76,
                    left: 20,
                    child: Text(
                      reading.cents != null
                          ? '${reading.cents! >= 0 ? "+" : ""}${reading.cents!.toStringAsFixed(1)} c'
                          : '-- c',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Center bottom: Tuning dropdown selector
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => InstrumentSettingsSheet.show(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151525),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${state.instrument.label}: ${state.currentTuning.name}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_drop_down, color: Color(0xFF6B6B9A), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToneGenerator(TunerState state) {
    final double keyboardHeight = _toneExpanded ? 320.0 : 48.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: keyboardHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C14),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        children: [
          // Header / Toggle bar
          GestureDetector(
            onTap: () {
              setState(() {
                _toneExpanded = !_toneExpanded;
              });
            },
            child: Container(
              height: 47,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: const Color(0xFF0F0F1A),
              child: Row(
                children: [
                  const Icon(Icons.music_note, color: Color(0xFF00E676), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Tone Generator',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _toneExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible keyboard and options content
          if (_toneExpanded)
            Expanded(
              child: Row(
                children: [
                  // Left side: wave selector sidebar
                  Container(
                    width: 64,
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
                      color: Color(0xFF09090F),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: WaveType.values.map((w) {
                        return WaveShapeButton(
                          type: w,
                          selected: _selectedWave,
                          onChanged: (newType) {
                            setState(() {
                              _selectedWave = newType;
                            });
                            // If currently playing, update tone generator waveform instantly
                            if (_playingMidi != null) {
                              _playTone(_playingMidi!);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  // Right side: Vertical scrollable keyboard
                  Expanded(
                    child: ListView.builder(
                      itemCount: _keyboardNotes.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, idx) {
                        final int midi = _keyboardNotes[idx];
                        final int noteVal = midi % 12;
                        final bool isBlack = [1, 3, 6, 8, 10].contains(noteVal);
                        final String label = _getNoteName(midi);
                        final bool isPlaying = _playingMidi == midi;

                        if (isBlack) {
                          return GestureDetector(
                            onTap: () => isPlaying ? _stopTone() : _playTone(midi),
                            child: Container(
                              height: 38,
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              child: Row(
                                children: [
                                  Container(
                                    width: MediaQuery.of(context).size.width * 0.52,
                                    decoration: BoxDecoration(
                                      color: isPlaying
                                          ? const Color(0xFF00E676).withOpacity(0.3)
                                          : const Color(0xFF040408),
                                      borderRadius: const BorderRadius.horizontal(
                                        right: Radius.circular(4),
                                      ),
                                      border: Border.all(
                                        color: isPlaying ? const Color(0xFF00E676) : Colors.white12,
                                        width: 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.only(right: 12),
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isPlaying ? const Color(0xFF00E676) : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          return GestureDetector(
                            onTap: () => isPlaying ? _stopTone() : _playTone(midi),
                            child: Container(
                              height: 46,
                              margin: const EdgeInsets.symmetric(vertical: 1),
                              decoration: BoxDecoration(
                                color: isPlaying
                                    ? const Color(0xFF00E676).withOpacity(0.2)
                                    : const Color(0xFF1E1E2C),
                                border: Border.all(
                                  color: isPlaying ? const Color(0xFF00E676) : Colors.white10,
                                  width: 1,
                                ),
                              ),
                              padding: const EdgeInsets.only(right: 16),
                              alignment: Alignment.centerRight,
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: isPlaying ? const Color(0xFF00E676) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Custom Painters & Helper Widgets
// ─────────────────────────────────────────────────────────────

class WaveShapeButton extends StatelessWidget {
  final WaveType type;
  final WaveType selected;
  final ValueChanged<WaveType> onChanged;

  const WaveShapeButton({
    super.key,
    required this.type,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = type == selected;
    return GestureDetector(
      onTap: () => onChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 6),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E676).withOpacity(0.15) : const Color(0xFF161625),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E676) : Colors.white10,
            width: 1.5,
          ),
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(20, 12),
            painter: WaveIconPainter(
              type: type,
              color: isSelected ? const Color(0xFF00E676) : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

class WaveIconPainter extends CustomPainter {
  final WaveType type;
  final Color color;

  WaveIconPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final h = size.height;
    final w = size.width;

    switch (type) {
      case WaveType.sine:
        path.moveTo(0, h / 2);
        path.quadraticBezierTo(w / 4, 0, w / 2, h / 2);
        path.quadraticBezierTo(3 * w / 4, h, w, h / 2);
        break;
      case WaveType.triangle:
        path.moveTo(0, h / 2);
        path.lineTo(w / 4, 0);
        path.lineTo(3 * w / 4, h);
        path.lineTo(w, h / 2);
        break;
      case WaveType.sawtooth:
        path.moveTo(0, h);
        path.lineTo(w / 2, 0);
        path.lineTo(w / 2, h);
        path.lineTo(w, 0);
        break;
      case WaveType.square:
        path.moveTo(0, h / 2);
        path.lineTo(0, 0);
        path.lineTo(w / 2, 0);
        path.lineTo(w / 2, h);
        path.lineTo(w, h);
        path.lineTo(w, h / 2);
        break;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Chromatic note tape vertical ribbon custom painter
class VerticalNoteTapePainter extends CustomPainter {
  final double? currentMidi;
  final double lastMidi;
  final Color accentColor;

  static const double noteSpacing = 36.0;
  static const List<String> noteNames = [
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'
  ];

  VerticalNoteTapePainter({
    required this.currentMidi,
    required this.lastMidi,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    // Use current midi if active, else default to last known midi value
    final double centerMidi = currentMidi ?? lastMidi;

    // 1. Draw central alignment pointer brackets
    final pointerPaint = Paint()
      ..color = currentMidi == null ? Colors.white24 : accentColor
      ..style = PaintingStyle.fill;

    // Draw small triangular arrows at center on the sides pointing in
    final pathLeft = Path()
      ..moveTo(4, cy - 6)
      ..lineTo(12, cy)
      ..lineTo(4, cy + 6)
      ..close();
    final pathRight = Path()
      ..moveTo(size.width - 4, cy - 6)
      ..lineTo(size.width - 12, cy)
      ..lineTo(size.width - 4, cy + 6)
      ..close();

    canvas.drawPath(pathLeft, pointerPaint);
    canvas.drawPath(pathRight, pointerPaint);

    // 2. Iterate and draw notes
    final int minMidi = (centerMidi - 8).floor().clamp(21, 108);
    final int maxMidi = (centerMidi + 8).ceil().clamp(21, 108);

    for (int k = minMidi; k <= maxMidi; k++) {
      final double y = cy - (k - centerMidi) * noteSpacing;

      // Check visibility bounds
      if (y < -20 || y > size.height + 20) continue;

      final int noteIndex = k % 12;
      final int octave = (k ~/ 12) - 1;
      final String noteName = noteNames[noteIndex];
      final String label = '$noteName$octave';

      final bool isTarget = currentMidi != null && k == currentMidi!.round();

      final TextStyle style = TextStyle(
        color: isTarget
            ? accentColor
            : (currentMidi == null ? Colors.white24 : Colors.white54),
        fontSize: isTarget ? 17 : 12,
        fontWeight: isTarget ? FontWeight.bold : FontWeight.w500,
      );

      final textSpan = TextSpan(
        text: isTarget ? '[ $label ]' : label,
        style: style,
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(cx - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant VerticalNoteTapePainter old) {
    return old.currentMidi != currentMidi ||
        old.lastMidi != lastMidi ||
        old.accentColor != accentColor;
  }
}

/// Semicircle ring & strings curves custom painter with interactive vibration
class VibratingStringCirclePainter extends CustomPainter {
  final List<StringTarget> strings;
  final double? currentFrequency;
  final Color accentColor;
  final double vibrationTime;
  final double toleranceCents;

  VibratingStringCirclePainter({
    required this.strings,
    required this.currentFrequency,
    required this.accentColor,
    required this.vibrationTime,
    required this.toleranceCents,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strings.isEmpty) return;

    final double cx = size.width / 2;
    final double cy = size.height * 0.44; // center circle a bit higher
    final double radius = math.min(cx * 0.82, cy * 0.82);

    // 1. Draw outer circle ring (chassis)
    final ringBgPaint = Paint()
      ..color = const Color(0xFF121222)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    canvas.drawCircle(Offset(cx, cy), radius, ringBgPaint);

    final ringOuterBorder = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), radius + 8, ringOuterBorder);
    canvas.drawCircle(Offset(cx, cy), radius - 8, ringOuterBorder);

    // 2. Space and render horizontal strings
    final double yStart = cy - radius * 0.65;
    final double yEnd = cy + radius * 0.65;
    final int count = strings.length;

    for (int i = 0; i < count; i++) {
      final StringTarget string = strings[i];
      final double yVal = yStart + (i / (count - 1)) * (yEnd - yStart);

      // Determine active string curve deflection
      double dy = 0.0;
      bool isStringActive = false;
      bool isStringInTune = false;

      if (currentFrequency != null) {
        final double centsDev = MusicUtils.centsBetween(currentFrequency!, string.frequency);

        // String reacts if within 140 cents of target frequency
        if (centsDev.abs() < 140.0) {
          isStringActive = true;
          isStringInTune = centsDev.abs() <= toleranceCents;

          // Normalized weight 0..1 based on proximity
          final double weight = 1.0 - (centsDev.abs() / 140.0);

          // Flat = curve downwards (dy > 0), Sharp = curve upwards (dy < 0)
          final double baseDeflection = -(centsDev / 140.0) * 32.0;
          dy = baseDeflection * weight;

          // Add oscilating vibration when sound is detected
          final double vibrationOsc = math.sin(vibrationTime * 28) * 4.5 * weight;
          dy += vibrationOsc;
        }
      }

      // Draw string label on the left end (inside circle)
      final labelSpan = TextSpan(
        text: string.label,
        style: TextStyle(
          color: isStringActive ? accentColor : Colors.white30,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(cx - radius * 0.90 - labelPainter.width, yVal - labelPainter.height / 2),
      );

      // Draw horizontal line (curved if active)
      final double x0 = cx - radius * 0.85;
      final double x1 = cx + radius * 0.85;

      final Color stringColor = isStringActive
          ? (isStringInTune ? const Color(0xFF00E676) : const Color(0xFFFF4B6E))
          : Colors.white.withOpacity(0.18);

      final stringPaint = Paint()
        ..color = stringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isStringActive ? 2.5 : 1.2;

      final path = Path();
      path.moveTo(x0, yVal);
      if (isStringActive) {
        // Curve control point shifts in Y coordinate
        path.quadraticBezierTo(cx, yVal + dy, x1, yVal);
      } else {
        path.lineTo(x1, yVal);
      }

      // Optional glow effect for active or in-tune strings
      if (isStringActive) {
        canvas.drawPath(
          path,
          Paint()
            ..color = stringColor.withOpacity(0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6.0,
        );
      }

      canvas.drawPath(path, stringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant VibratingStringCirclePainter old) {
    return old.currentFrequency != currentFrequency ||
        old.accentColor != accentColor ||
        old.vibrationTime != vibrationTime ||
        old.toleranceCents != toleranceCents ||
        old.strings != strings;
  }
}
