import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/chord_detector.dart';
import '../bloc/tuner_cubit.dart';
import '../bloc/tuner_state.dart';
import '../widgets/app_drawer.dart';

class _HeardNote {
  final int pitchClass;
  final double timestampMs;
  const _HeardNote(this.pitchClass, this.timestampMs);
}

/// Chord Matrix — a live grid of root notes (rows) x chord quality
/// (columns) that lights up the cell matching whatever chord the
/// player is currently strumming/arpeggiating.
///
/// Since the rest of this app's pitch detector (YIN) only tracks a
/// single monophonic fundamental at a time, true polyphonic detection
/// of a fully-voiced chord isn't possible from one analysis frame.
/// Instead, this screen keeps a short rolling window (about 1.6s) of
/// recently-detected single notes — covering a strum or arpeggio —
/// and feeds the *set* of distinct pitch classes heard in that window
/// to [ChordDetector], which matches it against known chord interval
/// patterns. This is what makes strumming through a chord (even one
/// string at a time) light up the right matrix cell, matching the
/// reference app's behavior.
class ChordMatrixScreen extends StatefulWidget {
  const ChordMatrixScreen({super.key});

  @override
  State<ChordMatrixScreen> createState() => _ChordMatrixScreenState();
}

class _ChordMatrixScreenState extends State<ChordMatrixScreen> {
  static const Duration _chordWindow = Duration(milliseconds: 1600);

  final Queue<_HeardNote> _recent = Queue<_HeardNote>();
  StreamSubscription<int>? _noteSub;
  Timer? _pruneTimer;
  final Stopwatch _clock = Stopwatch()..start();

  DetectedChord? _currentChord;
  double _glow = 0; // animated brightness for the lit cell

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TunerCubit>();
    // Listen to the cubit's RAW per-frame note stream — not its gated
    // `state.reading` stream. The tuner's stability gate (2 agreeing
    // frames within ±25 cents before anything is emitted) is tuned for
    // holding a single sustained note, and resets on every note change.
    // A strum or arpeggio changes pitch class every ~100-200ms, so that
    // gate was starving this screen's rolling window of almost every
    // note — which is why the matrix never lit up. The raw stream gives
    // us every detected note immediately, exactly like the reference
    // app's chord matrix behaves.
    _noteSub = cubit.rawNoteStream.listen(_onRawNote);
    _pruneTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _pruneOld();
      _recompute();
    });
  }

  void _onRawNote(int pitchClass) {
    _recent.addLast(_HeardNote(pitchClass, _clock.elapsedMilliseconds.toDouble()));
  }

  void _pruneOld() {
    final cutoff = _clock.elapsedMilliseconds - _chordWindow.inMilliseconds;
    while (_recent.isNotEmpty && _recent.first.timestampMs < cutoff) {
      _recent.removeFirst();
    }
  }

  void _recompute() {
    final heard = _recent.map((n) => n.pitchClass).toSet();
    final chord = ChordDetector.detect(heard);
    if (mounted) {
      setState(() {
        _currentChord = chord;
        // Pulse brightness — eases toward 1 when a chord is held,
        // decays toward 0 when nothing matches, giving the lit cell a
        // gentle fade rather than a hard on/off flicker.
        _glow = chord != null ? math.min(1.0, _glow + 0.25) : math.max(0.0, _glow - 0.15);
      });
    }
  }

  @override
  void dispose() {
    _noteSub?.cancel();
    _pruneTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      drawer: const AppDrawer(current: AppScreen.chordMatrix),
      body: SafeArea(
        child: BlocBuilder<TunerCubit, TunerState>(
          builder: (context, state) {
            return Column(
              children: [
                _Header(isListening: state.isListening),
                _ChordReadout(chord: _currentChord),
                Expanded(
                  child: state.isListening
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: _MatrixGrid(chord: _currentChord, glow: _glow),
                        )
                      : _IdlePrompt(onStart: () => context.read<TunerCubit>().start()),
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
            'Chord matrix',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
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

class _ChordReadout extends StatelessWidget {
  final DetectedChord? chord;
  const _ChordReadout({required this.chord});

  @override
  Widget build(BuildContext context) {
    final String text = chord == null
        ? 'Strum a chord…'
        : '${ChordDetector.pitchClassNames[chord!.rootPitchClass]} ${chord!.quality.label}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            color: chord == null ? Colors.white38 : const Color(0xFF00E676),
            fontSize: chord == null ? 16 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: chord == null ? 0 : -0.5,
          ),
        ),
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
          const Icon(Icons.grid_on_rounded, color: Color(0xFF3A3A5A), size: 40),
          const SizedBox(height: 12),
          const Text('Start the mic to detect chords',
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
        ],
      ),
    );
  }
}

/// The 12-row (root note) x 6-column (chord quality) grid.
class _MatrixGrid extends StatelessWidget {
  final DetectedChord? chord;
  final double glow;
  const _MatrixGrid({required this.chord, required this.glow});

  // Rows ordered B at top down to C at bottom (full descending chromatic
  // scale), matching the reference app's layout exactly.
  static const List<String> _rowLabels = [
    'B', 'Bb', 'A', 'G#', 'G', 'F#', 'F', 'E', 'Eb', 'D', 'C#', 'C',
  ];
  static const List<int> _rowPitchClasses = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0];

  static const List<ChordQuality> _columns = [
    ChordQuality.maj,
    ChordQuality.maj7,
    ChordQuality.dom7,
    ChordQuality.min,
    ChordQuality.min7,
    ChordQuality.dim7,
  ];
  static const List<String> _columnLabels = ['maj', 'maj7', 'dom7', 'min', 'min7', 'dim7'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double colW = (constraints.maxWidth - 44) / _columns.length;
      final double rowH = (constraints.maxHeight - 28) / _rowPitchClasses.length;

      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Row labels
                SizedBox(
                  width: 36,
                  child: Column(
                    children: _rowLabels
                        .map((l) => SizedBox(
                              height: rowH,
                              child: Center(
                                child: Text(l,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(width: 8),
                // Grid
                Expanded(
                  child: Column(
                    children: List.generate(_rowPitchClasses.length, (r) {
                      final int rootPc = _rowPitchClasses[r];
                      return SizedBox(
                        height: rowH,
                        child: Row(
                          children: List.generate(_columns.length, (c) {
                            final bool isLit = chord != null &&
                                chord!.rootPitchClass == rootPc &&
                                chord!.quality == _columns[c];
                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white10, width: 0.5),
                                  color: isLit
                                      ? _qualityColor(_columns[c]).withOpacity(0.25 + 0.65 * glow)
                                      : Colors.transparent,
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Column labels
          Row(
            children: [
              const SizedBox(width: 44),
              Expanded(
                child: Row(
                  children: _columnLabels
                      .map((l) => Expanded(
                            child: Center(
                              child: Text(l,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }

  Color _qualityColor(ChordQuality q) {
    switch (q) {
      case ChordQuality.maj:
        return const Color(0xFF9FE05D); // lime green, matches reference
      case ChordQuality.maj7:
        return const Color(0xFF5DE0A0);
      case ChordQuality.dom7:
        return const Color(0xFFE0C85D);
      case ChordQuality.min:
        return const Color(0xFFE0605D); // red, matches reference
      case ChordQuality.min7:
        return const Color(0xFFE0905D);
      case ChordQuality.dim7:
        return const Color(0xFFB05DE0);
    }
  }
}
