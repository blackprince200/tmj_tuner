import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/music_utils.dart';
import '../../core/wav_generator.dart';
import '../../data/models/tuning.dart';
import '../bloc/tuner_cubit.dart';
import '../bloc/tuner_state.dart';
import '../theme/app_colors.dart';
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

  // Vertical keyboard notes: C6 (84) down to C2 (36)
  final List<int> _keyboardNotes = List.generate(49, (i) => 84 - i);

  @override
  void initState() {
    super.initState();
    _vibrationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newCubit = context.read<TunerCubit>();
    if (_cubit != newCubit) {
      _cubit = newCubit;
      _cubit?.start();
    }
  }

  @override
  void dispose() {
    _vibrationCtrl.dispose();
    _audioPlayer.dispose();
    _cubit?.stop();
    super.dispose();
  }

  // Helper to determine active state color
  Color _getTuningColor(double? cents, double toleranceCents) {
    if (cents == null) return AppColors.primaryAccent; // Default active color (Orange) when selected but silent
    final double absCents = cents.abs();
    if (absCents <= toleranceCents) {
      return AppColors.tuningGreen; // Green
    } else if (absCents <= 10.0) {
      return AppColors.tuningYellow; // Yellow
    } else if (absCents <= 25.0) {
      return AppColors.primaryAccent; // Orange
    } else {
      return AppColors.tuningRed; // Red
    }
  }

  // Get note instructions string matching specifications
  String _getNoteInstruction(double? cents, double toleranceCents, String? noteName) {
    if (noteName == null || cents == null) {
      return 'Pick a string';
    }
    final double absCents = cents.abs();
    if (absCents <= toleranceCents) {
      return 'Perfect!';
    } else if (absCents <= 10.0) {
      return cents < 0 ? 'Almost there - tune up slightly.' : 'Almost there - tune down slightly.';
    } else if (absCents <= 25.0) {
      return cents < 0 ? 'A little too flat - tune up a bit.' : 'A little too sharp - tune down a bit.';
    } else {
      return cents < 0 ? 'Too flat - tune up.' : 'Too sharp - tune down.';
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

  // Show direct A4 calibration slider pop-up dialog
  void _showCalibrationDialog(TunerState state) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'A4 Calibration Reference',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${state.a4Reference.toStringAsFixed(0)} Hz',
                    style: const TextStyle(
                      color: AppColors.primaryAccent,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    min: 430,
                    max: 450,
                    divisions: 20,
                    value: state.a4Reference,
                    activeColor: AppColors.primaryAccent,
                    inactiveColor: Colors.white10,
                    onChanged: (val) {
                      setDialogState(() {
                        _cubit?.setA4Reference(val);
                      });
                      setState(() {}); // refresh TunerScreen
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.baseBackground,
      drawer: const AppDrawer(current: AppScreen.tuner),
      body: SafeArea(
        child: BlocBuilder<TunerCubit, TunerState>(
          builder: (context, state) {
            if (state.errorMessage != null) {
              return _buildError(context, state.errorMessage!);
            }
            return Stack(
              children: [
                Column(
                  children: [
                    // Top header bar
                    _buildTopBar(context, state),

                    // Central Status Meter (Pick a string, Perfect!, Flat/Sharp)
                    _buildStatusMeter(state),

                    // Fretboard neck layout with strings overlays
                    Expanded(
                      child: _buildGuitarFretboard(state),
                    ),

                    // Bottom bar navigation icons
                    _buildBottomBar(state),
                  ],
                ),

                // Collapsible Tone Generator keyboard panel (slides up over neck)
                if (_toneExpanded)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 56, // sits directly above the bottom navigation bar
                    height: 320,
                    child: _buildToneGenerator(state),
                  ),
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
                color: AppColors.tuningRed.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_off, size: 48, color: AppColors.tuningRed),
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
                backgroundColor: AppColors.primaryAccent,
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Guitar Tuner+',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mic capturing on/off toggle
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
              color: state.isListening ? AppColors.tuningGreen : Colors.white30,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          // Auto switch
          const Text(
            'Auto',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(width: 4),
          Switch(
            value: state.autoMode,
            onChanged: (val) => _cubit?.setAutoMode(val),
            activeColor: AppColors.primaryAccent,
            activeTrackColor: AppColors.primaryAccent.withOpacity(0.3),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.white10,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMeter(TunerState state) {
    final reading = state.reading;
    final double? cents = reading.centsFromTarget ?? reading.cents;
    final Color stateColor = _getTuningColor(cents, state.toleranceCents);
    final Color meterColor = cents == null ? const Color(0xFF444444) : stateColor;
    final bool hasSignal = reading.frequency != null && reading.frequency! > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // Circular progress/note display
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _vibrationCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(116, 116),
                      painter: TuningMeterPainter(
                        cents: cents,
                        noteName: reading.noteName,
                        stateColor: meterColor,
                        animationValue: _vibrationCtrl.value,
                        toleranceCents: state.toleranceCents,
                      ),
                    );
                  },
                ),
                Text(
                  reading.noteName ?? 'E',
                  style: TextStyle(
                    color: hasSignal ? AppColors.baseBackground : AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Large instruction text
          Text(
            _getNoteInstruction(cents, state.toleranceCents, reading.noteName),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.normal,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          // Note frequency subtext
          Text(
            hasSignal ? '${reading.frequency!.toStringAsFixed(2)} Hz' : '0.0 Hz',
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 13,
              fontWeight: FontWeight.w300,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuitarFretboard(TunerState state) {
    final reading = state.reading;
    final double? cents = reading.centsFromTarget ?? reading.cents;
    final Color stateColor = _getTuningColor(cents, state.toleranceCents);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Height is bounded. Render portrait AspectRatio container centered
        return Center(
          child: AspectRatio(
            aspectRatio: 1664 / 2578,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Guitar neck background image
                  Positioned.fill(
                    child: Image.asset(
                      'assets/ui/guitar.png',
                      fit: BoxFit.fill,
                    ),
                  ),

                  // Strings overlay custom painter
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        return AnimatedBuilder(
                          animation: _vibrationCtrl,
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size(box.maxWidth, box.maxHeight),
                              painter: GuitarStringsPainter(
                                strings: state.currentTuning.strings,
                                currentFrequency: reading.frequency,
                                stateColor: stateColor,
                                vibrationTime: _vibrationCtrl.value * 2 * math.pi,
                                toleranceCents: state.toleranceCents,
                                state: state,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Positioned string selection chips overlay (E, A, D, G, B, E)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        return _buildStringChips(state, box.maxWidth, box.maxHeight);
                      },
                    ),
                  ),

                  // Dreadnought Standard preset button overlay near bottom of neck
                  Positioned(
                    bottom: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12, width: 1.0),
                      ),
                      child: Text(
                        state.currentTuning.name.contains('Standard')
                            ? 'Dreadnought in Standard'
                            : state.currentTuning.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStringChips(TunerState state, double W, double H) {
    final int stringCount = state.currentTuning.strings.length;
    if (stringCount == 0) return const SizedBox.shrink();

    // Mapcents to tuning state color
    final double? cents = state.reading.centsFromTarget ?? state.reading.cents;

    // Default string chip positions for standard 6 strings (aligned with pegs)
    final List<double> xGuitarCoords = [0.100, 0.258, 0.406, 0.560, 0.702, 0.850];

    // Compute midpoint horizontal string position at y = 0.72
    // Interpolation factor at y = 0.72 between y = 1.0 (bottom) and y = 0.245 (nut)
    // t = (1.0 - 0.72) / (1.0 - 0.245) = 0.28 / 0.755 = 0.3708
    // xMid = 0.6292 * xBottom + 0.3708 * xNut
    final List<double> xMidCoords = List.generate(stringCount, (i) {
      if (stringCount == 6) {
        final List<double> xNutCoords = [0.312, 0.385, 0.450, 0.519, 0.600, 0.660];
        return 0.6292 * xGuitarCoords[i] + 0.3708 * xNutCoords[i];
      } else {
        // Fallback for non 6-strings (e.g. Bass 4 strings) - distribute evenly
        final double xB = 0.100 + (i / (stringCount - 1)) * 0.750;
        final double xN = 0.312 + (i / (stringCount - 1)) * 0.348;
        return 0.6292 * xB + 0.3708 * xN;
      }
    });

    return Stack(
      children: List.generate(stringCount, (i) {
        final string = state.currentTuning.strings[i];
        final double x = xMidCoords[i];
        final bool isChipActive = state.autoMode
            ? state.reading.matchedString == string
            : state.selectedString == string;

        final Color chipBgColor = isChipActive
            ? _getTuningColor(cents, state.toleranceCents)
            : AppColors.surfaceCard.withOpacity(0.8);

        return Positioned(
          left: x * W - 15,
          top: 0.72 * H - 17, // Adjusted slightly for the taller pick shape
          child: GestureDetector(
            onTap: () => _cubit?.selectString(string),
            child: CustomPaint(
              size: const Size(30, 34),
              painter: GuitarPickPainter(
                color: chipBgColor,
                borderColor: isChipActive ? Colors.white : Colors.white12,
                borderWidth: isChipActive ? 1.5 : 1.0,
                hasShadow: isChipActive,
              ),
              child: Container(
                width: 30,
                height: 34,
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5), // Offset text upwards from the bottom point
                  child: Text(
                    string.noteNameOnly,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: isChipActive ? FontWeight.bold : FontWeight.normal,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBottomBar(TunerState state) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: AppColors.dividersBorders, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Tuning Fork: toggles Tone Generator Vertical Keyboard
          IconButton(
            onPressed: () {
              setState(() {
                _toneExpanded = !_toneExpanded;
              });
            },
            icon: Icon(
              Icons.music_note,
              color: _toneExpanded ? AppColors.primaryAccent : AppColors.textSecondary,
              size: 24,
            ),
          ),

          // Peg icon dial: Taps open direct calibration slider pop-up
          GestureDetector(
            onTap: () => _showCalibrationDialog(state),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.tune_rounded,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.a4Reference.toStringAsFixed(0)} Hz',
                  style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Settings gear: Opens instrument config modal sheet
          IconButton(
            onPressed: () => InstrumentSettingsSheet.show(context),
            icon: const Icon(
              Icons.settings,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToneGenerator(TunerState state) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.baseBackground,
        border: Border(
          top: BorderSide(color: AppColors.dividersBorders, width: 0.5),
          bottom: BorderSide(color: AppColors.dividersBorders, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Header title bar
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.surfaceCard,
            child: Row(
              children: [
                const Icon(Icons.music_note, color: AppColors.primaryAccent, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Tone Generator Synth',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _toneExpanded = false;
                    });
                    _stopTone();
                  },
                  icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Collapsible keyboard and options content
          Expanded(
            child: Row(
              children: [
                // Left side: wave selector sidebar
                Container(
                  width: 64,
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AppColors.dividersBorders, width: 0.5)),
                    color: AppColors.baseBackground,
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
                          // If playing, update tone generator waveform instantly
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
                                        ? AppColors.primaryAccent.withOpacity(0.3)
                                        : AppColors.baseBackground,
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(4),
                                    ),
                                    border: Border.all(
                                      color: isPlaying ? AppColors.primaryAccent : Colors.white12,
                                      width: 1,
                                    ),
                                  ),
                                  padding: const EdgeInsets.only(right: 12),
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: isPlaying ? AppColors.primaryAccent : AppColors.textSecondary,
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
                                  ? AppColors.primaryAccent.withOpacity(0.2)
                                  : AppColors.surfaceCard,
                              border: Border.all(
                                color: isPlaying ? AppColors.primaryAccent : AppColors.dividersBorders,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.only(right: 16),
                            alignment: Alignment.centerRight,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isPlaying ? AppColors.primaryAccent : AppColors.textPrimary,
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

class TuningMeterPainter extends CustomPainter {
  final double? cents;
  final String? noteName;
  final Color stateColor;
  final double animationValue;
  final double toleranceCents;

  TuningMeterPainter({
    required this.cents,
    required this.noteName,
    required this.stateColor,
    required this.animationValue,
    required this.toleranceCents,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 8;

    final bool isInTune = cents != null && cents!.abs() <= toleranceCents;

    // 1. Draw concentric expanding sound ripples if in tune
    if (isInTune) {
      final ripplePaint = Paint()
        ..color = stateColor.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      // Draw 3 expanding ripples
      for (int i = 0; i < 3; i++) {
        final double progress = (animationValue + i / 3.0) % 1.0;
        final double r = radius + 8.0 + (progress * 240.0);
        final double opacity = (1.0 - progress) * 0.15;
        ripplePaint.color = stateColor.withOpacity(opacity);
        canvas.drawCircle(Offset(cx, cy), r, ripplePaint);
      }
    }

    // 2. Draw outer dotted circle
    final dashPaint = Paint()
      ..color = stateColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final double dashRadius = radius + 8.0;
    const int dashCount = 28;
    final double angleOffset = animationValue * 2 * math.pi;

    for (int i = 0; i < dashCount; i++) {
      final double angle = (i * 2 * math.pi / dashCount) + angleOffset;
      final double x = cx + dashRadius * math.cos(angle);
      final double y = cy + dashRadius * math.sin(angle);
      canvas.drawCircle(Offset(x, y), 1.5, dashPaint);
    }

    // Calculate horizontal offset based on cents deviation
    double horizontalOffset = 0.0;
    if (cents != null && !isInTune) {
      // Shift left if flat, right if sharp. Maximum shift is 36 pixels.
      final double clampedCents = cents!.clamp(-50.0, 50.0);
      horizontalOffset = (clampedCents / 50.0) * 36.0;
    }

    // 3. Draw central status filled circle (shifted horizontally)
    final circlePaint = Paint()
      ..color = stateColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + horizontalOffset, cy), radius, circlePaint);

    // 4. Draw deviation indicator pointer on outer ring
    if (cents != null) {
      // Scale cents deviation to angle: -50 cents = -60 degrees, +50 cents = +60 degrees
      final double clampedCents = cents!.clamp(-50.0, 50.0);
      final double indicatorAngle = -math.pi / 2 + (clampedCents / 50.0) * (math.pi / 3.2);

      final double ix = cx + dashRadius * math.cos(indicatorAngle);
      final double iy = cy + dashRadius * math.sin(indicatorAngle);

      final indicatorPaint = Paint()
        ..color = stateColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(ix, iy), 4.5, indicatorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TuningMeterPainter old) {
    return old.cents != cents ||
        old.noteName != noteName ||
        old.stateColor != stateColor ||
        old.animationValue != animationValue ||
        old.toleranceCents != toleranceCents;
  }
}

/// Dynamic custom strings and pegs overlay painter
class GuitarStringsPainter extends CustomPainter {
  final List<StringTarget> strings;
  final double? currentFrequency;
  final Color stateColor;
  final double vibrationTime;
  final double toleranceCents;
  final TunerState state;

  // Visual layout constants verified for cropped guitar.png (1664x2578)
  static const double yNut = 0.245;
  static const List<double> xNut = [0.312, 0.385, 0.450, 0.519, 0.600, 0.660];
  static const List<double> xBottom = [0.100, 0.258, 0.406, 0.560, 0.702, 0.850];
  static const List<Offset> pegs = [
    Offset(0.250, 0.198),
    Offset(0.270, 0.138),
    Offset(0.285, 0.078),
    Offset(0.715, 0.078),
    Offset(0.730, 0.138),
    Offset(0.750, 0.198),
  ];

  // String gauges/thickness (thick E2 to thin E4)
  static const List<double> gauges = [2.2, 1.8, 1.4, 1.1, 0.8, 0.5];

  GuitarStringsPainter({
    required this.strings,
    required this.currentFrequency,
    required this.stateColor,
    required this.vibrationTime,
    required this.toleranceCents,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strings.isEmpty) return;

    final double W = size.width;
    final double H = size.height;

    // Draw 6 strings
    for (int i = 0; i < 6; i++) {
      // Check if string is active
      bool isStringActive = false;
      if (state.autoMode) {
        isStringActive = state.reading.matchedString == strings[i];
      } else {
        isStringActive = state.selectedString == strings[i];
      }

      final double bx = xBottom[i] * W;
      final double by = H;
      final double nx = xNut[i] * W;
      final double ny = yNut * H;
      final double px = pegs[i].dx * W;
      final double py = pegs[i].dy * H;

      double dx = 0.0;
      if (isStringActive && currentFrequency != null) {
        final double centsDev = MusicUtils.centsBetween(currentFrequency!, strings[i].frequency);
        if (centsDev.abs() < 120.0) {
          final double weight = 1.0 - (centsDev.abs() / 120.0);
          // Horizontal deflection on neck
          final double baseDeflection = (centsDev / 120.0) * 10.0;
          dx = baseDeflection * weight;
          // High-frequency vibration oscillation
          dx += math.sin(vibrationTime * 32) * 2.2 * weight;
        }
      }

      // 1. Nut to bottom (vibrating fretboard segment)
      final pathFret = Path();
      pathFret.moveTo(bx, by);
      if (isStringActive && dx.abs() > 0.01) {
        final double mx = ((bx + nx) / 2) + dx;
        final double my = (by + ny) / 2;
        pathFret.quadraticBezierTo(mx, my, nx, ny);
      } else {
        pathFret.lineTo(nx, ny);
      }

      // Draw string line
      final stringPaint = Paint()
        ..color = isStringActive ? stateColor : Colors.white.withOpacity(0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isStringActive ? gauges[i] * 1.5 + 1.0 : gauges[i]
        ..strokeCap = StrokeCap.round;

      // Draw active glow
      if (isStringActive) {
        canvas.drawPath(
          pathFret,
          Paint()
            ..color = stateColor.withOpacity(0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = gauges[i] * 4.0 + 4.0
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawPath(pathFret, stringPaint);

      // 2. Nut to peg (straight headstock segment)
      final pathHead = Path()
        ..moveTo(nx, ny)
        ..lineTo(px, py);

      final headPaint = Paint()
        ..color = isStringActive ? stateColor : Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isStringActive ? gauges[i] * 1.3 : gauges[i]
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(pathHead, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GuitarStringsPainter old) {
    return old.currentFrequency != currentFrequency ||
        old.stateColor != stateColor ||
        old.vibrationTime != vibrationTime ||
        old.toleranceCents != toleranceCents ||
        old.strings != strings ||
        old.state != state;
  }
}

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
          color: isSelected ? AppColors.primaryAccent.withOpacity(0.15) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primaryAccent : AppColors.dividersBorders,
            width: 1.5,
          ),
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(20, 12),
            painter: WaveIconPainter(
              type: type,
              color: isSelected ? AppColors.primaryAccent : AppColors.textSecondary,
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

class GuitarPickPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final bool hasShadow;

  GuitarPickPainter({
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    this.hasShadow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final double w = size.width;
    final double h = size.height;

    final path = Path();
    // A guitar pick pointing downwards
    path.moveTo(w / 2, h * 0.1);
    path.cubicTo(w * 0.85, 0, w, h * 0.15, w, h * 0.4);
    path.cubicTo(w, h * 0.75, w * 0.65, h, w / 2, h);
    path.cubicTo(w * 0.35, h, 0, h * 0.75, 0, h * 0.4);
    path.cubicTo(0, h * 0.15, w * 0.15, 0, w / 2, h * 0.1);
    path.close();

    if (hasShadow) {
      canvas.drawPath(
        path.shift(const Offset(0, 2.0)),
        Paint()
          ..color = color.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );
    }

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant GuitarPickPainter old) {
    return old.color != color ||
        old.borderColor != borderColor ||
        old.borderWidth != borderWidth ||
        old.hasShadow != hasShadow;
  }
}

