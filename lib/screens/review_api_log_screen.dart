import 'package:flutter/material.dart';

import '../services/review_router_log.dart';
import '../utils/app_theme.dart';

/// RouterOS sentences executed by the jb.admin simulator.
class ReviewApiLogScreen extends StatelessWidget {
  const ReviewApiLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkScaffold : null,
      appBar: AppBar(
        title: const Text('RouterOS API log'),
      ),
      body: AnimatedBuilder(
        animation: ReviewRouterLog.instance,
        builder: (context, _) {
          final entries = ReviewRouterLog.instance.entries.reversed.toList();
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No RouterOS commands yet.\n'
                  'Ban, unban, speed, lock, or Wi-Fi will append the exact '
                  'API sentence here.\n\n'
                  'هنوز دستوری نیست. مسدود کردن، سرعت، قفل اتصال یا وای‌فای '
                  'همان جملهٔ API را اینجا می‌نویسد.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: entries.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'Newest first\n'
                  'جدیدترین بالا است. تاریخ و ساعت، زمان محلی همین گوشی است.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? const Color(0xFFB7C3D1) : const Color(0xFF44515F),
                  ),
                );
              }
              final entry = entries[index - 1];
              final ink = isDark ? const Color(0xFFE8EEF6) : const Color(0xFF1C2834);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B2430) : const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.stamp,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: entry.label.contains('DeltaSIB')
                              ? const Color(0xFF0B7A4B)
                              : const Color(0xFF8A5A00),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        '${entry.command.join('\n')}\n${entry.detail}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
