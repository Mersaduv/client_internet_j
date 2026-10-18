import 'package:flutter/material.dart';

import '../utils/shamsi_date.dart';
import '../utils/sib_package_insight.dart';

/// کارت بسته روی صفحهٔ اصلی: عنوان، نام سرویس، نوار سبزِ مانده، تاریخ و روزها.
class SibPackageCard extends StatelessWidget {
  const SibPackageCard({super.key, required this.insight});

  final SibPackageInsight insight;

  @override
  Widget build(BuildContext context) {
    final remain = insight.remainingRatio.clamp(0.0, 1.0);
    final showHero = insight.heroLabel != insight.title;
    final start = ShamsiDate.label(insight.start);
    final end = ShamsiDate.label(insight.end, withTime: true);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 360;
    final titleSize = compact ? 15.0 : 16.0;
    final heroSize = compact ? 22.0 : 26.0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 16, compact ? 12 : 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF163E6E), Color(0xFF0E2748)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              insight.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showHero) ...[
              const SizedBox(height: 6),
              Text(
                insight.heroLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: heroSize,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ],
            if (insight.kind == SibPackageKind.volume && insight.remainBytes != null) ...[
              const SizedBox(height: 6),
              Text(
                'مانده ${SibPackageInsight.formatBytes(insight.remainBytes, compact: true)} از ${SibPackageInsight.formatBytes(insight.totalBytes, compact: true)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: const Color(0xFFB7F7C8), fontSize: compact ? 12 : 13),
              ),
            ],
            if (insight.dailyBytes != null) ...[
              const SizedBox(height: 4),
              Text(
                'محدودیت روزانه ${SibPackageInsight.formatBytes(insight.dailyBytes, compact: true)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: const Color(0xFF8FD6FF), fontSize: compact ? 12 : 13),
              ),
            ],
            if (insight.noteSecondary != null) ...[
              const SizedBox(height: 2),
              Text(
                insight.noteSecondary!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'گراف مصرف بسته شما',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: compact ? 14 : 15),
            ),
            const SizedBox(height: 10),
            _RemainingBar(ratio: remain),
            const SizedBox(height: 12),
            _pair(
              'شروع: $start',
              'ختم: $end',
              compact: compact,
            ),
            const SizedBox(height: 8),
            _pair(
              'مدت کل بسته: ${SibPackageInsight.faDigits(insight.totalDays ?? 0)} روز',
              'مصرف شده: ${SibPackageInsight.faDigits(insight.usedDays ?? 0)} روز',
              compact: compact,
              strong: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pair(
    String start,
    String end, {
    required bool compact,
    bool strong = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _meta(start, strong: strong, compact: compact)),
        const SizedBox(width: 8),
        Expanded(child: _meta(end, strong: strong, compact: compact, alignEnd: true)),
      ],
    );
  }

  Widget _meta(
    String text, {
    bool strong = false,
    bool alignEnd = false,
    bool compact = false,
  }) {
    return Text(
      text,
      textAlign: alignEnd ? TextAlign.left : TextAlign.right,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? (strong ? 12 : 11.5) : (strong ? 13.5 : 12.5),
        fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
        height: 1.35,
      ),
    );
  }
}

class _RemainingBar extends StatelessWidget {
  const _RemainingBar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final width = ratio <= 0 ? 0.0 : ratio.clamp(0.04, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 10,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFFC5D0DC)),
              FractionallySizedBox(
                alignment: Alignment.centerRight,
                widthFactor: width,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFB6FF8A), Color(0xFF3DDC6A), Color(0xFF14C48A)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SibPackageCardSkeleton extends StatefulWidget {
  const SibPackageCardSkeleton({super.key});

  @override
  State<SibPackageCardSkeleton> createState() => _SibPackageCardSkeletonState();
}

class _SibPackageCardSkeletonState extends State<SibPackageCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 16, compact ? 12 : 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF163E6E), Color(0xFF0E2748)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bone(120, 14),
                const SizedBox(height: 10),
                _bone(compact ? 160 : 190, compact ? 22 : 26),
                const SizedBox(height: 18),
                _bone(130, 12),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _bone(double.infinity, 10, radius: 99),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _bone(double.infinity, 12)),
                    const SizedBox(width: 12),
                    Expanded(child: _bone(double.infinity, 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _bone(double.infinity, 14)),
                    const SizedBox(width: 12),
                    Expanded(child: _bone(double.infinity, 14)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bone(double width, double height, {double radius = 8}) {
    final slide = _shimmer.value;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-1.2 + (slide * 2.4), 0),
          end: Alignment(-0.2 + (slide * 2.4), 0),
          colors: const [
            Color(0xFF1C4C78),
            Color(0xFF3D739F),
            Color(0xFF1C4C78),
          ],
        ),
      ),
    );
  }
}

