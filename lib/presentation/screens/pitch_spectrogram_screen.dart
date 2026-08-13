import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/tuner_cubit.dart';
import '../bloc/tuner_state.dart';
import '../widgets/app_drawer.dart';

/// A single point in the scrolling pitch history.
class _PitchPoint {
  final double timestampMs;
  final double? frequency; // null = silence at this timestamp
  /// RMS amplitude [0..1] — drives variable spike thickness.
  final double amplitude;
  const _PitchPoint(this.timestampMs, this.frequency, {this.amplitude = 0.0});
}

class PitchSpectrogramScreen extends StatefulWidget {
  const PitchSpectrogramScreen({super.key});

  @override
  State<PitchSpectrogramScreen> createState() => _PitchSpectrogramScreenState();
}

class _PitchSpectrogramScreenState extends State<PitchSpectrogramScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _historyWindow = Duration(seconds: 12);

  final Queue<_PitchPoint> _history = Queue<_PitchPoint>();
  StreamSubscription<TunerState>? _sub;
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch()..start();

  // Track whether any new data arrived since last frame — lets us skip
  // setState calls during silence when the display is just scrolling.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TunerCubit>();
    _sub = cubit.stream.listen(_onState);

    // Ticker fires once per vsync pulse — no drift, no double-fires.
    _ticker = createTicker((_) {
      _pruneOld();
      if (mounted) setState(() { _dirty = false; });
    })..start();
  }

  void _onState(TunerState state) {
    final freq = state.reading.frequency;
    _history.addLast(_PitchPoint(
      _clock.elapsedMilliseconds.toDouble(),
      freq,
      amplitude: state.reading.amplitude,
    ));
    _dirty = true;
    _pruneOld();
  }

  void _pruneOld() {
    final cutoff = _clock.elapsedMilliseconds - _historyWindow.inMilliseconds;
    while (_history.isNotEmpty && _history.first.timestampMs < cutoff) {
      _history.removeFirst();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      drawer: const AppDrawer(current: AppScreen.spectrogram),
      body: SafeArea(
        child: BlocBuilder<TunerCubit, TunerState>(
          builder: (context, state) {
            return Column(
              children: [
                _Header(isListening: state.isListening),
                Expanded(
                  child: state.isListening
                      // RepaintBoundary gives the spectrogram its own
                      // raster layer — header/footer touches don't
                      // trigger a full spectrogram repaint.
                      ? RepaintBoundary(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _SpectrogramPainter(
                              history: _history.toList(growable: false),
                              nowMs: _clock.elapsedMilliseconds.toDouble(),
                              windowMs: _historyWindow.inMilliseconds.toDouble(),
                              a4Reference: state.a4Reference,
                            ),
                          ),
                        )
                      : _IdlePrompt(
                          onStart: () => context.read<TunerCubit>().start()),
                ),
                _Footer(state: state),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Static widgets (unchanged) ───────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isListening;
  const _Header({required this.isListening});

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
            'Pitch spectrogram',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening ? const Color(0xFF00E676) : Colors.white24,
            ),
          ),
          Text(
            isListening ? 'Live' : 'Paused',
            style: TextStyle(
              color: isListening ? const Color(0xFF00E676) : Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
          const Icon(Icons.ssid_chart_rounded,
              color: Color(0xFF3A3A5A), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Start the mic to see live pitch history',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
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

class _Footer extends StatelessWidget {
  final TunerState state;
  const _Footer({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TunerCubit>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FooterButton(
            icon: state.isListening
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            label: state.isListening ? 'Listening' : 'Start',
            active: state.isListening,
            onTap: () =>
                state.isListening ? cubit.stop() : cubit.start(),
          ),
        ],
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FooterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00E67622)
              : const Color(0xFF151525),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: active ? const Color(0xFF00E676) : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active
                    ? const Color(0xFF00E676)
                    : Colors.white54,
                size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: active
                        ? const Color(0xFF00E676)
                        : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Painter ──────────────────────────────────────────────────────────

/// Scrolling chroma painter — optimised for 60 fps on mid-range phones.
///
/// Key performance choices:
/// • Two Paint objects allocated once, mutated per spike (no per-spike new).
/// • NO maskFilter blur — replaced with a plain wide low-opacity stroke.
/// • 12 TextPainter label objects built once in the constructor, reused
///   every frame (label text changes only when last-octave changes, which
///   is handled by rebuilding the painter via shouldRepaint).
/// • shouldRepaint returns false when history list identity and nowMs
///   are both unchanged.
class _SpectrogramPainter extends CustomPainter {
  final List<_PitchPoint> history;
  final double nowMs;
  final double windowMs;
  final double a4Reference;

  // Row order (top→bottom) and accidental spelling matching the reference.
  static const List<String> _rowNames = [
    'B', 'Bb', 'A', 'G#', 'G', 'F#', 'F', 'E', 'Eb', 'D', 'C#', 'C',
  ];
  static const List<int> _rowPitchClass = [
    11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
  ];

  // ── Pre-allocated paint objects — mutated in the loop, never re-created ──
  final Paint _solidPaint = Paint()..strokeCap = StrokeCap.butt;
  final Paint _glowPaint  = Paint()..strokeCap = StrokeCap.butt;
  final Paint _gridPaint  = Paint()
    ..color = const ui.Color(0x14FFFFFF)  // white @ 8 % opacity
    ..strokeWidth = 0.5;
  final Paint _bgPaint    = Paint()..color = const Color(0xFF050508);
  final Paint _cursorPaint = Paint()
    ..color = const Color(0x8000E676)     // green @ 50 % opacity
    ..strokeWidth = 2;

  // ── Cached rainbow colours — computed once, indexed by pitch class ──
  static final List<Color> _pitchColors = List<Color>.generate(12, (pc) {
    final double hue = (81 + 30 * pc) % 360;
    return HSVColor.fromAHSV(1.0, hue, 0.72, 1.0).toColor();
  });

  // ── Cached per-row label TextPainters ──
  // Built in the constructor with the octave suffix known at paint time;
  // shouldRepaint returns true whenever lastOctaves changes so they get
  // rebuilt only when actually needed.
  final List<TextPainter> _labelPainters;

  _SpectrogramPainter({
    required this.history,
    required this.nowMs,
    required this.windowMs,
    required this.a4Reference,
  }) : _labelPainters = _buildLabels(history);

  /// Build 12 pre-laid-out TextPainters from the current history in one pass.
  static List<TextPainter> _buildLabels(List<_PitchPoint> history) {
    // Walk history newest-first to find each row's current octave.
    final List<int?> lastOctaveForPc = List<int?>.filled(12, null);
    for (int i = history.length - 1; i >= 0; i--) {
      final freq = history[i].frequency;
      if (freq == null) continue;
      final int midi = (69 + 12 * (math.log(freq / 440.0) / math.ln2)).round();
      final int pc = midi % 12;
      if (lastOctaveForPc[pc] == null) {
        lastOctaveForPc[pc] = (midi ~/ 12) - 1;
      }
      if (lastOctaveForPc.every((o) => o != null)) break;
    }

    return List<TextPainter>.generate(12, (row) {
      final int pc = _rowPitchClass[row];
      final int? octave = lastOctaveForPc[pc];
      final String label =
          octave == null ? _rowNames[row] : '${_rowNames[row]}$octave';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xD1FFFFFF), // ~82 % white — bright & readable
            fontSize: 17,            // fixed size; clamp happens at layout
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 40);
      return tp;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Offset.zero & size, _bgPaint);

    final double rowH = size.height / 12;

    // ── Grid lines + labels ──────────────────────────────────────────
    for (int row = 0; row < 12; row++) {
      final double yBottom = (row + 1) * rowH;
      canvas.drawLine(
          Offset(0, yBottom), Offset(size.width, yBottom), _gridPaint);

      final double yCenter = (row + 0.5) * rowH;
      final tp = _labelPainters[row];
      tp.paint(canvas, Offset(6, yCenter - tp.height / 2));
    }

    // ── Spike loop — two reused Paint objects, no blur ───────────────
    for (final point in history) {
      final freq = point.frequency;
      if (freq == null) continue;

      final double x = _timeToX(point.timestampMs, size.width);
      final double midi = _freqToMidiFloat(freq);

      // Amplitude → visual weight [0..1] via sqrt curve.
      final double rawAmp = point.amplitude.clamp(0.0005, 0.15);
      final double t =
          math.sqrt((rawAmp - 0.0005) / (0.15 - 0.0005));

      final double spikeW  = 1.0 + t * 3.5;           // 1.0 → 4.5 px
      final double spikeH  = rowH * (0.55 + t * 0.37); // 55 % → 92 % rowH
      final double glowW   = spikeW * 2.8;
      // Glow alpha: wider stroke at lower opacity is cheaper than blur
      // and looks nearly identical on a dark background.
      final double glowAlpha = 0.15 + t * 0.22;        // 0.15 → 0.37

      final double rowPos   = _midiToRowPos(midi);
      final double rowIndex = rowPos.floorToDouble();
      final double subRow   = rowPos - rowIndex;
      final double margin   = (rowH - spikeH) / 2;
      final double yTop     =
          rowIndex * rowH + margin + (rowH - 2 * margin - spikeH) * subRow;

      final int pitchClass = midi.round() % 12;
      final Color color = _pitchColors[pitchClass];

      // Glow — wide, semi-transparent, NO blur filter
      _glowPaint
        ..color = color.withOpacity(glowAlpha)
        ..strokeWidth = glowW;
      canvas.drawLine(Offset(x, yTop), Offset(x, yTop + spikeH), _glowPaint);

      // Solid spike
      _solidPaint
        ..color = color
        ..strokeWidth = spikeW;
      canvas.drawLine(
          Offset(x, yTop), Offset(x, yTop + spikeH), _solidPaint);
    }

    // ── "Now" cursor ──────────────────────────────────────────────────
    canvas.drawLine(Offset(size.width - 2, 0),
        Offset(size.width - 2, size.height), _cursorPaint);
  }

  double _timeToX(double timestampMs, double width) {
    final double age = nowMs - timestampMs;
    return (1 - age / windowMs).clamp(0.0, 1.0) * width;
  }

  double _freqToMidiFloat(double freq) =>
      69 + 12 * (math.log(freq / a4Reference) / math.ln2);

  double _midiToRowPos(double midi) {
    final double pitchClass = midi % 12;
    return (11 - pitchClass) % 12;
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) {
    // Skip rasterisation entirely when nothing changed.
    return !identical(old.history, history) || old.nowMs != nowMs;
  }
}
