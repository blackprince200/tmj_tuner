import 'package:flutter/material.dart';
import '../../data/models/tuning.dart';

/// Guitar headstock-style string selector with frequency labels.
/// Shows note name + target Hz under each button for clarity.
/// Left column = low strings, right column = high strings.
class StringSelector extends StatelessWidget {
  final List<StringTarget> strings;
  final StringTarget? matched;
  final StringTarget? selected;
  final bool autoMode;
  final Color matchedColor;
  final double buttonDiameter;
  final double verticalGap;
  final double centerGap;
  final void Function(StringTarget) onSelect;

  const StringSelector({
    super.key,
    required this.strings,
    required this.matched,
    required this.selected,
    required this.autoMode,
    required this.matchedColor,
    required this.onSelect,
    this.buttonDiameter = 52,
    this.verticalGap = 6,
    this.centerGap = 64,
  });

  bool _isActive(StringTarget s) {
    if (autoMode) return matched == s;
    return selected == s;
  }

  @override
  Widget build(BuildContext context) {
    if (strings.isEmpty) return const SizedBox.shrink();

    final int half = (strings.length / 2).ceil();
    final leftStrings = strings.sublist(0, half);
    final rightStrings = strings.sublist(half);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: leftStrings
                .map((s) => _StringButton(
                      string: s,
                      isActive: _isActive(s),
                      activeColor: matchedColor,
                      diameter: buttonDiameter,
                      verticalGap: verticalGap,
                      onTap: () => onSelect(s),
                    ))
                .toList(),
          ),
          // Fixed-width gap rather than Expanded — this widget can be
          // measured under unbounded width constraints (e.g. inside a
          // FittedBox, which sizes its child at its natural/intrinsic
          // size before scaling), and Expanded requires a bounded
          // parent width to compute its flex share. A fixed gap keeps
          // layout valid in both bounded and unbounded contexts.
          SizedBox(width: centerGap),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: rightStrings
                .map((s) => _StringButton(
                      string: s,
                      isActive: _isActive(s),
                      activeColor: matchedColor,
                      diameter: buttonDiameter,
                      verticalGap: verticalGap,
                      onTap: () => onSelect(s),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _StringButton extends StatelessWidget {
  final StringTarget string;
  final bool isActive;
  final Color activeColor;
  final double diameter;
  final double verticalGap;
  final VoidCallback onTap;

  const _StringButton({
    required this.string,
    required this.isActive,
    required this.activeColor,
    required this.diameter,
    required this.verticalGap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.symmetric(vertical: verticalGap / 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circle button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? activeColor.withOpacity(0.2)
                    : const Color(0xFF1A1A2E),
                border: Border.all(
                  color: isActive ? activeColor : const Color(0xFF2A2A40),
                  width: isActive ? 2.5 : 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: activeColor.withOpacity(0.35),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  string.noteNameOnly,
                  style: TextStyle(
                    color: isActive ? activeColor : Colors.white54,
                    fontWeight: FontWeight.w800,
                    fontSize: diameter * 0.33,
                  ),
                ),
              ),
            ),
            // Frequency label below button
            const SizedBox(height: 2),
            Text(
              '${string.frequency.toStringAsFixed(0)}Hz',
              style: TextStyle(
                color: isActive
                    ? activeColor.withOpacity(0.8)
                    : const Color(0xFF4A4A6A),
                fontSize: (diameter * 0.18).clamp(8.0, 11.0),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
