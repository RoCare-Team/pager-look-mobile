import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'app_card.dart';

/// Circular avatar: network photo when available, initials otherwise.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.name, this.imageUrl, this.size = 40});

  final String? name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = mediaUrl(imageUrl);
    final fallback = Center(
      child: Text(
        initials(name),
        style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: AppColors.brand600),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppColors.brand50, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: url == null ? fallback : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// PagerLook logo.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 32, this.white = false});

  final double height;
  final bool white;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      white ? 'assets/images/logo_white.png' : 'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text(
        'PagerLook',
        style: TextStyle(
          fontSize: height * 0.6,
          fontWeight: FontWeight.w700,
          color: white ? Colors.white : AppColors.brand600,
        ),
      ),
    );
  }
}

/// Score gauge (web: `EmployeeScoreGauge`) — an arc with the value in the middle.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.value, required this.max, this.size = 160, this.label, this.color});

  final num value;
  final num max;
  final double size;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0, 1).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(fraction, color ?? AppColors.brand600),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.round()}',
                style: TextStyle(
                  fontSize: size * 0.24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkStrong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(label ?? 'of ${max.round()}', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.color);

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final base = Paint()
      ..color = AppColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, base);
    if (fraction > 0) canvas.drawArc(rect, start, sweep * fraction, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}

/// Linear progress with label and percentage.
class LabeledProgress extends StatelessWidget {
  const LabeledProgress(
      {super.key, required this.label, required this.value, this.max = 100, this.color, this.trailing});

  final String label;
  final num value;
  final num max;
  final Color? color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkBody))),
            Text(
              trailing ?? '${value.round()}/${max.round()}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: AppColors.hairline,
            color: color ?? AppColors.brand600,
          ),
        ),
      ],
    );
  }
}

/// A point on a [MiniBarChart].
class ChartPoint {
  const ChartPoint(this.label, this.value, {this.secondary});
  final String label;
  final num value;

  /// Optional second series drawn beside the first (e.g. verified vs total).
  final num? secondary;
}

/// Dependency-free bar chart for trends (insights, dashboards).
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.points,
    this.height = 160,
    this.color = AppColors.brand600,
    this.secondaryColor = AppColors.brand100,
  });

  final List<ChartPoint> points;
  final double height;
  final Color color;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No data yet', style: TextStyle(color: AppColors.inkFaint))),
      );
    }
    final maxValue =
        points.map((p) => math.max(p.value.toDouble(), (p.secondary ?? 0).toDouble())).fold<double>(0, math.max);
    final scale = maxValue <= 0 ? 1.0 : maxValue;

    Widget bar(num v, Color c) => Flexible(
          child: FractionallySizedBox(
            heightFactor: (v / scale).clamp(0.02, 1).toDouble(),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ),
          ),
        );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((p) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                children: [
                  Text(
                    '${p.value.round()}',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (p.secondary != null) bar(p.secondary!, secondaryColor),
                        bar(p.value, color),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Horizontal breakdown bars (department split, status breakdown).
class BreakdownBars extends StatelessWidget {
  const BreakdownBars({super.key, required this.items, this.color = AppColors.brand600});

  /// label → count
  final Map<String, num> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('No data yet', style: TextStyle(color: AppColors.inkFaint))),
      );
    }
    final total = items.values.fold<num>(0, (a, b) => a + b);
    return Column(
      children: items.entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LabeledProgress(
                label: e.key,
                value: e.value,
                max: total <= 0 ? 1 : total,
                color: color,
                trailing: '${e.value.round()}',
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Light summary card — a small progress ring beside a headline and a short
/// caption. The standard replacement for full-bleed navy hero banners.
class ProgressSummaryCard extends StatelessWidget {
  const ProgressSummaryCard({
    super.key,
    required this.progress,
    required this.centerLabel,
    required this.title,
    this.caption,
    this.footer,
  });

  /// 0..1
  final double progress;
  final String centerLabel;
  final String title;
  final String? caption;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: value,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.brand50,
                      color: value >= 1 ? AppColors.success : AppColors.brand600,
                    ),
                    Center(
                      child: Text(
                        centerLabel,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 3),
                      Text(caption!, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}
