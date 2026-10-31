import 'package:flutter/material.dart';

class MetricChartCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final List<double> trend;
  final String badgeLabel;
  final bool? badgeIsPositive;
  final List<Color> backgroundColors;
  final Color borderColor;
  final String? subtitle;
  final bool legacyDashboardStyle;
  final VoidCallback? onTap;

  const MetricChartCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    this.trend = const [],
    this.badgeLabel = '',
    this.badgeIsPositive,
    this.backgroundColors = const [Color(0xFF1E3B2E), Color(0xFF0F1713)],
    this.borderColor = const Color(0xFF2A4D3A),
    this.subtitle,
    this.legacyDashboardStyle = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (legacyDashboardStyle) return _buildLegacyCard();

    final positive = badgeIsPositive == true;
    final negative = badgeIsPositive == false;
    final badgeColor = positive
        ? const Color(0xFF16865B)
        : negative
        ? const Color(0xFFD64545)
        : const Color(0xFF687386);
    final badgeBackground = positive
        ? const Color(0xFFE7F6EF)
        : negative
        ? const Color(0xFFFCEBEC)
        : const Color(0xFFF0F2F5);
    final borderRadius = BorderRadius.circular(22);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0xFFE9EDF2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF172B4D).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF687386),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badgeLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badgeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) => Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF151B26),
                      fontSize: constraints.maxWidth < 150 ? 21 : 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _MetricTrendPainter(values: trend, color: color),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ver detalles',
                        style: const TextStyle(
                          color: Color(0xFF687386),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      negative
                          ? Icons.trending_down_rounded
                          : Icons.trending_up_rounded,
                      color: negative ? const Color(0xFFD64545) : color,
                      size: 19,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyCard() {
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
                    painter: _MetricTrendPainter(
                      values: trend,
                      color: color,
                      glow: true,
                    ),
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
  final bool glow;

  const _MetricTrendPainter({
    required this.values,
    required this.color,
    this.glow = false,
  });

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
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: glow ? 0.4 : 0.2),
            color.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    if (glow) {
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
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = glow ? 3.5 : 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  List<Offset> _pointsFor(Size size) {
    if (values.isEmpty) {
      return [
        Offset(0, size.height * 0.75),
        Offset(size.width, size.height * 0.75),
      ];
    }
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
    return [
      for (var index = 0; index < values.length; index++)
        Offset(
          size.width * index / (values.length - 1),
          range == 0
              ? size.height * 0.52
              : verticalPadding +
                    (maximum - values[index]) / range * chartHeight,
        ),
    ];
  }

  @override
  bool shouldRepaint(_MetricTrendPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      oldDelegate.values != values;
}
