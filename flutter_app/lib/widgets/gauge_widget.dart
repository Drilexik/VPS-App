import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GaugeWidget extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final double size;

  const GaugeWidget({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.size = 110,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(value: value.clamp(0, 100), color: color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${value.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: size * 0.155,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: size * 0.095,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;

  static const _startAngle = pi * 0.75;
  static const _sweepTotal = pi * 1.5;

  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeW = 9.0;

    final bgPaint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal,
      false,
      bgPaint,
    );

    if (value > 0) {
      final valPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _sweepTotal * (value / 100),
        false,
        valPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

Color gaugeColor(double pct) {
  if (pct < 60) return AppColors.accent;
  if (pct < 80) return AppColors.warning;
  return AppColors.danger;
}
