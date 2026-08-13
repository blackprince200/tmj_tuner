import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/tuning.dart';
import '../bloc/tuner_cubit.dart';
import '../bloc/tuner_state.dart';

class InstrumentSettingsSheet extends StatelessWidget {
  const InstrumentSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    final cubit = context.read<TunerCubit>();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16162A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const InstrumentSettingsSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TunerCubit>();

    return BlocBuilder<TunerCubit, TunerState>(
      builder: (context, state) {
        return SafeArea(
          child: SingleChildScrollView(
            // Settings sheets are explicitly allowed to scroll — unlike
            // the main tuner screen, this isn't a real-time display and
            // the content list grows with however many tunings/options
            // exist, so a fixed adaptive layout isn't the right fit here.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Settings',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                _SectionLabel('Instrument'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: Instrument.values.map((inst) {
                    final bool sel = state.instrument == inst;
                    return _Chip(
                      label: inst.label,
                      selected: sel,
                      onTap: () => cubit.setInstrument(inst),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                if (state.availableTunings.isNotEmpty && state.availableTunings.first.strings.isNotEmpty) ...[
                  _SectionLabel('Tuning'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: state.availableTunings.map((t) {
                      final bool sel = state.currentTuning.name == t.name;
                      return _Chip(
                        label: t.name,
                        selected: sel,
                        onTap: () => cubit.setTuning(t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                _SectionLabel('Calibration  A4 = ${state.a4Reference.toStringAsFixed(0)} Hz'),
                Slider(
                  min: 430,
                  max: 450,
                  divisions: 20,
                  value: state.a4Reference,
                  activeColor: const Color(0xFF2BBE8C),
                  label: state.a4Reference.toStringAsFixed(0),
                  onChanged: cubit.setA4Reference,
                ),
                _SectionLabel('Tolerance  ±${state.toleranceCents.toStringAsFixed(0)} cents'),
                Slider(
                  min: 2,
                  max: 15,
                  divisions: 13,
                  value: state.toleranceCents,
                  activeColor: const Color(0xFF2BBE8C),
                  label: state.toleranceCents.toStringAsFixed(0),
                  onChanged: cubit.setToleranceCents,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2BBE8C).withOpacity(0.2) : const Color(0xFF2A2A3A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF2BBE8C) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF2BBE8C) : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

