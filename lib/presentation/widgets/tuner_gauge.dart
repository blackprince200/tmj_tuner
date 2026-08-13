import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Professional arc-based tuner gauge inspired by FastTune's UI design.
/// 
/// Features:
/// - Semicircular arc with graduated tick marks (-50 to +50 cents)
/// - Animated sweep needle with smooth physics-like motion
/// - Central "sweet spot" green zone highlight
/// - Frequency display at the bottom of the arc
/// - Live cents deviation indicator with directional arrows
/// - Color-coded glow effects (green = in tune, red = off)
class TunerGauge extends StatefulWidget {
  final double? cents;
  final Color color;
  final double toleranceCents;
  final double height;
  final double? frequency;

  const TunerGauge({
    super.key,
    required this.cents,
    required this.color,
    required this.height,
    this.toleranceCents = 5,
    this.frequency,
  });

  @override
  State<TunerGauge> createState() => _TunerGaugeState();
}

class _TunerGaugeState extends State<TunerGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _needleAnim;
  double _prevCents = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _needleAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(TunerGauge old) {
    super.didUpdateWidget(old);
    final double target = widget.cents ?? 0;
    if ((target - _prevCents).abs() > 0.3) {
      _needleAnim = Tween<double>(begin: _prevCents, end: target).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
      _ctrl.forward(from: 0);
      _prevCents = target;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _needleAnim,
      builder: (context, _) {
        return SizedBox(
          width: double.infinity,
          height: widget.height,
          child: CustomPaint(
            painter: _ArcGaugePainter(
              cents: widget.cents == null ? null : _needleAnim.value,
              needleColor: widget.color,
              toleranceCents: widget.toleranceCents,
              frequency: widget.frequency,
            ),
          ),
        );
      },
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double? cents;
  final Color needleColor;
  final double toleranceCents;
  final double? frequency;

  static const double _maxCents = 55.0;
  // Arc spans from -130° to -50° (180° sweep centred at bottom)
  static const double _startAngleDeg = 145.0; // left extreme = flat
  static const double _sweepDeg = 250.0;       // full sweep

  _ArcGaugePainter({
    required this.cents,
    required this.needleColor,
    required this.toleranceCents,
    required this.frequency,
  });

  double _centsToAngle(double c) {
    final norm = (c / _maxCents).clamp(-1.0, 1.0);
    // Map -1..+1 to startAngle..startAngle+sweep
    return (_startAngleDeg + _sweepDeg / 2 + norm * _sweepDeg / 2) *
        math.pi /
        180;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Push the arc center a bit below the widget so only the top half shows
    final cy = size.height * 0.88;
    final radius = math.min(cx * 0.88, cy * 0.92);

    // ── Background ──────────────────────────────────────────────────
    final bg = Paint()..color = const Color(0xFF0D0D1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    // ── Sweet-spot arc (green zone) ──────────────────────────────────
    final sweetFrac = toleranceCents / _maxCents;
    final sweetSweepRad = sweetFrac * (_sweepDeg * math.pi / 180);
    final centerAngleRad = (_startAngleDeg + _sweepDeg / 2) * math.pi / 180;

    final sweetPaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.13
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      centerAngleRad - sweetSweepRad,
      sweetSweepRad * 2,
      false,
      sweetPaint,
    );

    // ── Main arc track ───────────────────────────────────────────────
    final trackPaint = Paint()
      ..color = const Color(0xFF1E1E35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.045
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      _startAngleDeg * math.pi / 180,
      _sweepDeg * math.pi / 180,
      false,
      trackPaint,
    );

    // ── Tick marks ───────────────────────────────────────────────────
    final List<double> majorTicks = [-50, -25, 0, 25, 50];
    final List<double> minorTicks = [
      -50, -40, -30, -20, -10, 0, 10, 20, 30, 40, 50
    ];

    for (final tc in minorTicks) {
      final angle = _centsToAngle(tc);
      final isMajor = majorTicks.contains(tc);
      final isCenter = tc == 0;

      final innerR = radius * (isMajor ? 0.72 : 0.80);
      final outerR = radius * (isCenter ? 0.62 : 0.92);

      final x1 = cx + innerR * math.cos(angle);
      final y1 = cy + innerR * math.sin(angle);
      final x2 = cx + outerR * math.cos(angle);
      final y2 = cy + outerR * math.sin(angle);

      Color tickColor;
      if (isCenter) {
        tickColor = const Color(0xFF00E676).withOpacity(0.9);
      } else if (isMajor) {
        tickColor = Colors.white.withOpacity(0.55);
      } else {
        tickColor = Colors.white.withOpacity(0.25);
      }

      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        Paint()
          ..color = tickColor
          ..strokeWidth = isCenter ? 2.5 : (isMajor ? 2.0 : 1.2)
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── Tick labels ──────────────────────────────────────────────────
    final labelCents = [-50.0, -25.0, 0.0, 25.0, 50.0];
    final labelTexts = ['-50', '-25', '0', '+25', '+50'];
    for (int i = 0; i < labelCents.length; i++) {
      final angle = _centsToAngle(labelCents[i]);
      final labelR = radius * 0.58;
      final lx = cx + labelR * math.cos(angle);
      final ly = cy + labelR * math.sin(angle);
      _drawCenteredText(
        canvas,
        labelTexts[i],
        Offset(lx, ly),
        TextStyle(
          color: labelCents[i] == 0
              ? const Color(0xFF00E676).withOpacity(0.8)
              : Colors.white.withOpacity(0.38),
          fontSize: radius * 0.095,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      );
    }

    // ── 'b' and '#' end labels ───────────────────────────────────────
    const labelStyle = TextStyle(
      color: Color(0xFF6B6B9A),
      fontSize: 13,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
    );
    final leftAngle = _startAngleDeg * math.pi / 180;
    final rightAngle = (_startAngleDeg + _sweepDeg) * math.pi / 180;
    _drawCenteredText(
        canvas, '♭', Offset(cx + radius * 1.08 * math.cos(leftAngle), cy + radius * 1.08 * math.sin(leftAngle)), labelStyle);
    _drawCenteredText(
        canvas, '♯', Offset(cx + radius * 1.08 * math.cos(rightAngle), cy + radius * 1.08 * math.sin(rightAngle)), labelStyle);

    // ── Filled arc progress (colored fill showing deviation) ─────────
    if (cents != null) {
      final clamped = cents!.clamp(-_maxCents, _maxCents);
      final centerRad = centerAngleRad;
      final needleRad = _centsToAngle(clamped);

      final startArc = clamped < 0 ? needleRad : centerRad;
      final sweepArc = (needleRad - centerRad).abs();

      if (sweepArc > 0.01) {
        final progressPaint = Paint()
          ..color = needleColor.withOpacity(0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.045
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          startArc,
          sweepArc,
          false,
          progressPaint,
        );
      }
    }

    // ── Needle ───────────────────────────────────────────────────────
    final double needleAngle = cents == null ? centerAngleRad : _centsToAngle(cents!.clamp(-_maxCents, _maxCents));
    final double needleLen = radius * 0.88;
    final nx = cx + needleLen * math.cos(needleAngle);
    final ny = cy + needleLen * math.sin(needleAngle);

    if (cents != null) {
      // Glow
      canvas.drawLine(
        Offset(cx, cy),
        Offset(nx, ny),
        Paint()
          ..color = needleColor.withOpacity(0.20)
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Needle body
    canvas.drawLine(
      Offset(cx, cy),
      Offset(nx, ny),
      Paint()
        ..color = cents == null ? Colors.white24 : needleColor
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );

    // Pivot circle
    canvas.drawCircle(
      Offset(cx, cy),
      radius * 0.045,
      Paint()..color = cents == null ? const Color(0xFF2A2A40) : needleColor,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      radius * 0.025,
      Paint()..color = Colors.white,
    );

    // ── Frequency readout at arc bottom ──────────────────────────────
    if (frequency != null) {
      _drawCenteredText(
        canvas,
        '${frequency!.toStringAsFixed(1)} Hz',
        Offset(cx, cy - radius * 0.12),
        TextStyle(
          color: needleColor.withOpacity(0.8),
          fontSize: radius * 0.11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      );
    }
  }

  void _drawCenteredText(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter old) {
    return old.cents != cents ||
        old.needleColor != needleColor ||
        old.toleranceCents != toleranceCents ||
        old.frequency != frequency;
  }
}
