import 'package:flutter/material.dart';

class MetricChartCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final List<double> trend;
  final List<Color> backgroundColors;
  final Color borderColor;
  final String? subtitle;
  final VoidCallback? onTap;

  const MetricChartCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    this.trend = const [],
    this.backgroundColors = const [Color(0xFF1E3B2E), Color(0xFF0F1713)],
    this.borderColor = const Color(0xFF2A4D3A),
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: backgroundColors,
        ),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_outward_rounded, color: color, size: 18),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 58,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _MetricTrendPainter(values: trend, color: color),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricTrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  const _MetricTrendPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final points = _pointsFor(size);
    if (points.isEmpty) return;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      final midpoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      linePath.quadraticBezierTo(
        current.dx,
        current.dy,
        midpoint.dx,
        midpoint.dy,
      );
    }
    linePath.lineTo(points.last.dx, points.last.dy);

    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.4), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawPath(areaPath, areaPaint);

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  List<Offset> _pointsFor(Size size) {
    if (values.isEmpty) return const [];
    if (values.length == 1) {
      return [
        Offset(0, size.height * 0.55),
        Offset(size.width, size.height * 0.45),
      ];
    }

    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final range = maximum - minimum;
    final verticalPadding = size.height * 0.18;
    final chartHeight = size.height - verticalPadding * 2;
    final usableRange = range == 0 ? 1.0 : range;

    return [
      for (var index = 0; index < values.length; index++)
        Offset(
          size.width * index / (values.length - 1),
          range == 0
              ? size.height * 0.52
              : verticalPadding +
                    (maximum - values[index]) / usableRange * chartHeight,
        ),
    ];
  }

  @override
  bool shouldRepaint(_MetricTrendPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.values != values;
}
