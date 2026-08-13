import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/detected_pitch.dart';
import '../bloc/tuner_cubit.dart';
import '../bloc/tuner_state.dart';
import '../widgets/app_drawer.dart';

enum _StrobeMode { sineByNote, sineByHarmonic, bowtie }

/// Strobe Tuner — a true multi-mode strobe display combined with a
/// chromatic ribbon-style note readout, for rapid hands-free tuning.
///
/// Tap the display to cycle through 3 visual modes:
///  1. Stacked sine waves, one per octave of the detected note (E2..E7
///     style) — a *stationary* wave means perfectly in tune; a wave
///     that visibly drifts left/right means the pitch is off, and the
///     drift speed/direction shows how far and which way.
///  2. Stacked sine waves, one per harmonic multiple (1x..6x) of the
///     fundamental — same drift behavior, organized by harmonic
///     number instead of absolute octave.
///  3. "Bowtie" strobe bars — the classic mechanical-strobe-disc look,
///     where each band's bowtie shape drifts left/right when out of
///     tune and freezes when locked on pitch.
///
/// HOW THE STROBE EFFECT IS SIMULATED:
/// A real strobe tuner makes a printed pattern appear to rotate by
/// flashing a light at (target frequency - actual frequency) Hz. We
/// can't flash a physical light, but the same visual principle works
/// directly in a continuously-animated canvas: each band's pattern is
/// phase-shifted every frame by an amount proportional to the *cents
/// deviation* from the target pitch. At 0 cents the phase doesn't
/// move (frozen pattern = in tune). The further off pitch, the faster
/// the pattern visibly drifts, and the sign of the deviation sets the
/// drift direction — exactly mirroring a real strobe disc.
class StrobeTunerScreen extends StatefulWidget {
  const StrobeTunerScreen({super.key});

  @override
  State<StrobeTunerScreen> createState() => _StrobeTunerScreenState();
}

class _StrobeTunerScreenState extends State<StrobeTunerScreen>
    with SingleTickerProviderStateMixin {
  _StrobeMode _mode = _StrobeMode.sineByNote;
  late Ticker _ticker;
  double _phaseAccumulator = 0;
  Duration _lastTick = Duration.zero;
  double _currentCents = 0; // smoothed for animation purposes

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final double dtSeconds =
        (_lastTick == Duration.zero) ? 0 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    // Phase speed proportional to cents-off — this is the "rotation
    // speed" of the simulated strobe disc. Scaled so that a ±50 cent
    // deviation produces a clearly visible, but not nauseating, drift.
    final double speed = _currentCents * 0.06;
    _phaseAccumulator += speed * dtSeconds;

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _cycleMode() {
    setState(() {
      _mode = _StrobeMode.values[(_mode.index + 1) % _StrobeMode.values.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      drawer: const AppDrawer(current: AppScreen.strobe),
      body: SafeArea(
        child: BlocBuilder<TunerCubit, TunerState>(
          builder: (context, state) {
            final reading = state.reading;
            final double? cents = reading.centsFromTarget ?? reading.cents;
            _currentCents = cents ?? 0;
            final bool inTune = reading.status == InTuneStatus.inTune;
            final Color accent = inTune
                ? const Color(0xFF00E676)
                : (cents != null && cents.abs() > 25
                    ? const Color(0xFFFF4B6E)
                    : const Color(0xFFFFC247));

            return Column(
              children: [
                _Header(onModeTap: _cycleMode, mode: _mode),
                _InfoBar(reading: reading, accent: accent),
                Expanded(
                  child: state.isListening
                      ? GestureDetector(
                          onTap: _cycleMode,
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _StrobePainter(
                              mode: _mode,
                              phase: _phaseAccumulator,
                              cents: cents,
                              hasSignal: reading.frequency != null,
                              accent: accent,
                            ),
                          ),
                        )
                      : _IdlePrompt(onStart: () => context.read<TunerCubit>().start()),
                ),
                _ModeFooter(mode: _mode, onTap: _cycleMode, state: state),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onModeTap;
  final _StrobeMode mode;
  const _Header({required this.onModeTap, required this.mode});

  String get _modeLabel {
    switch (mode) {
      case _StrobeMode.sineByNote:
        return 'By octave';
      case _StrobeMode.sineByHarmonic:
        return 'By harmonic';
      case _StrobeMode.bowtie:
        return 'Strobe bands';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: Colors.white70),
            ),
          ),
          const Text(
            'Strobe tuner',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onModeTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF151525),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_modeLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.swap_horiz_rounded, color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top info bar: hollow/outline note name (fills solid when in tune),
/// flat/sharp markers, Hz reading, and cents offset — mirrors the
/// reference app's strobe-tuner header exactly.
class _InfoBar extends StatelessWidget {
  final TunerReading reading;
  final Color accent;
  const _InfoBar({required this.reading, required this.accent});

  @override
  Widget build(BuildContext context) {
    final bool hasSignal = reading.noteName != null;
    final double? cents = reading.centsFromTarget ?? reading.cents;
    final bool inTune = reading.status == InTuneStatus.inTune;

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasSignal)
            Positioned(
              top: 8,
              child: _ConvergeMarkers(inTune: inTune, color: accent, pointingDown: true),
            ),
          if (hasSignal)
            Positioned(
              bottom: 8,
              child: _ConvergeMarkers(inTune: inTune, color: accent, pointingDown: false),
            ),

          Container(width: 1, height: 100, color: Colors.white24),

          if (hasSignal)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('♭',
                          style: TextStyle(
                              color: accent.withOpacity(0.7), fontSize: 16, fontStyle: FontStyle.italic)),
                      Text('3',
                          style: TextStyle(color: accent.withOpacity(0.5), fontSize: 11)),
                    ],
                  ),
                ),
                _OutlineNote(
                  text: reading.noteName ?? '',
                  filled: inTune,
                  color: accent,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${reading.octave}',
                          style: TextStyle(color: accent.withOpacity(0.85), fontSize: 22, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            )
          else
            const Text('—', style: TextStyle(color: Colors.white24, fontSize: 40)),

          Positioned(
            top: 8,
            right: 0,
            child: Text(
              hasSignal ? '${reading.frequency!.toStringAsFixed(1)} Hz' : '',
              style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 0,
            child: Text(
              (hasSignal && cents != null)
                  ? '${cents >= 0 ? "+" : ""}${cents.toStringAsFixed(1)} c'
                  : '',
              style: TextStyle(color: accent.withOpacity(0.85), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConvergeMarkers extends StatelessWidget {
  final bool inTune;
  final Color color;
  final bool pointingDown;
  const _ConvergeMarkers({required this.inTune, required this.color, required this.pointingDown});

  @override
  Widget build(BuildContext context) {
    final double gap = inTune ? 0 : 14;
    final icon = Icon(Icons.play_arrow_rounded, color: color, size: 18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(angle: math.pi, child: icon),
        SizedBox(width: gap),
        icon,
      ],
    );
  }
}

/// Note name rendered as a hollow outline when not in tune, and a
/// solid fill when locked on pitch — matching the reference app's
/// "fills in when in tune" effect.
class _OutlineNote extends StatelessWidget {
  final String text;
  final bool filled;
  final Color color;
  const _OutlineNote({required this.text, required this.filled, required this.color});

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Text(
        text,
        style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: color),
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w800,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      ),
    );
  }
}

class _IdlePrompt extends StatelessWidget {
  final VoidCallback onStart;
  const _IdlePrompt({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.waves_rounded, color: Color(0xFF3A3A5A), size: 40),
          const SizedBox(height: 12),
          const Text('Start the mic to see the strobe display',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onStart,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E676),
              side: const BorderSide(color: Color(0xFF00E676)),
            ),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Start listening'),
          ),
        ],
      ),
    );
  }
}

class _ModeFooter extends StatelessWidget {
  final _StrobeMode mode;
  final VoidCallback onTap;
  final TunerState state;
  const _ModeFooter({required this.mode, required this.onTap, required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TunerCubit>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => state.isListening ? cubit.stop() : cubit.start(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: state.isListening ? const Color(0xFF00E67622) : const Color(0xFF151525),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: state.isListening ? const Color(0xFF00E676) : Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(state.isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                      color: state.isListening ? const Color(0xFF00E676) : Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Text(state.isListening ? 'Listening' : 'Start',
                      style: TextStyle(
                          color: state.isListening ? const Color(0xFF00E676) : Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Tap display to change mode',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
        ],
      ),
    );
  }
}

/// Paints whichever strobe mode is currently selected.
class _StrobePainter extends CustomPainter {
  final _StrobeMode mode;
  final double phase;
  final double? cents;
  final bool hasSignal;
  final Color accent;

  static const int _bandCount = 6;
  static const List<Color> _bandColors = [
    Color(0xFF7FE0C8),
    Color(0xFFE0E060),
    Color(0xFFE07F7F),
    Color(0xFF7FC8E0),
    Color(0xFFC07FE0),
    Color(0xFFE07FC0),
  ];

  const _StrobePainter({
    required this.mode,
    required this.phase,
    required this.cents,
    required this.hasSignal,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050508));

    if (!hasSignal) {
      _drawIdleNoise(canvas, size);
      return;
    }

    switch (mode) {
      case _StrobeMode.sineByNote:
      case _StrobeMode.sineByHarmonic:
        _paintSineStack(canvas, size);
        break;
      case _StrobeMode.bowtie:
        _paintBowtie(canvas, size);
        break;
    }
  }

  void _drawIdleNoise(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.04);
    final rnd = math.Random(42);
    for (int i = 0; i < 80; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 1, paint);
    }
  }

  void _paintSineStack(Canvas canvas, Size size) {
    final double bandH = size.height / _bandCount;

    for (int i = 0; i < _bandCount; i++) {
      final int harmonic = i + 1;
      final double cy = size.height - bandH * i - bandH / 2;
      final color = _bandColors[i % _bandColors.length];

      // Higher harmonics show more wave cycles and amplified phase
      // drift — mirrors how a real strobe disc's higher bands "spin"
      // faster for the same pitch error, since higher harmonics move
      // more Hz per cent than the fundamental.
      final double cyclesAcrossScreen = 2.0 + harmonic * 0.8;
      final double bandPhase = phase * harmonic;

      final path = Path();
      const int steps = 120;
      for (int s = 0; s <= steps; s++) {
        final double t = s / steps;
        final double x = t * size.width;
        final double angle = (t * cyclesAcrossScreen * 2 * math.pi) + bandPhase;
        final double amp = bandH * 0.32;
        final double y = cy + math.sin(angle) * amp;
        if (s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );

      final label = mode == _StrobeMode.sineByHarmonic ? '${harmonic}x' : _octaveLabelFor(harmonic);
      _drawLabel(canvas, label, Offset(size.width / 2 - 12, cy - bandH * 0.36), color);
    }
  }

  String _octaveLabelFor(int harmonic) {
    // Cosmetic band labels mirroring the reference app's "octave"
    // style mode — true note naming for the fundamental is shown in
    // the info bar above; these are relative octave markers.
    const labels = ['·2', '·3', '·4', '·5', '·6', '·7'];
    return labels[(harmonic - 1).clamp(0, labels.length - 1)];
  }

  void _paintBowtie(Canvas canvas, Size size) {
    final double bandH = size.height / _bandCount;

    for (int i = 0; i < _bandCount; i++) {
      final int harmonic = i + 1;
      final double top = size.height - bandH * (i + 1);
      final double bottom = top + bandH;
      final color = _bandColors[i % _bandColors.length];

      final tickPaint = Paint()
        ..color = Colors.white.withOpacity(0.05)
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), tickPaint);
      }

      // Bowtie shape drifts horizontally with accumulated phase; at
      // 0 cents the phase doesn't advance so it sits still (locked).
      final double bandPhase = phase * harmonic;
      final double rawX = size.width / 2 + (bandPhase * 14);
      final double wrappedX = rawX % size.width;

      final double halfW = bandH * 0.85;
      final path = Path()
        ..moveTo(wrappedX, top)
        ..lineTo(wrappedX + halfW, top)
        ..lineTo(wrappedX, (top + bottom) / 2)
        ..lineTo(wrappedX + halfW, bottom)
        ..lineTo(wrappedX, bottom)
        ..lineTo(wrappedX - halfW, (top + bottom) / 2)
        ..close();

      canvas.drawPath(path, Paint()..color = color.withOpacity(0.85));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      _drawLabel(canvas, '${harmonic}x', Offset(size.width - 36, (top + bottom) / 2 - 7), Colors.white60);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _StrobePainter old) => true;
}
