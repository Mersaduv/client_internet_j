import 'package:flutter/material.dart';

import '../screens/review_api_log_screen.dart';
import '../utils/app_theme.dart';

/// Explains that jb.admin is not on a MikroTik LAN and may continue in the simulator.
///
/// Dismissing the dialog continues into the simulator. [allowStayOnLogin] is
/// only for the login screen, where the tester can still choose a real router.
Future<bool> showReviewSimulationDialog(
  BuildContext context, {
  bool allowStayOnLogin = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _ReviewSimulationDialog(
      allowStayOnLogin: allowStayOnLogin,
    ),
  ).then((value) => value != false);
}

class _ReviewSimulationDialog extends StatelessWidget {
  const _ReviewSimulationDialog({required this.allowStayOnLogin});

  final bool allowStayOnLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppTheme.darkScaffold : null,
      title: const Text('Not connected to MikroTik\nبه میکروتیک وصل نیستید'),
      content: const SingleChildScrollView(
        child: Text(
          'This phone is not on a MikroTik LAN, so the router API '
          '(Winbox / port 2752) did not answer.\n'
          'این گوشی روی شبکهٔ محلی میکروتیک نیست و API روتر '
          '(Winbox / پورت ۸۷۲۸) پاسخ نداد.\n\n'
          'You are using the review account. Connected devices, banned '
          'devices, ban / unban, speed limit, lock new connections, and '
          'Wi-Fi will run on a simulator on this phone. Each action sends '
          'the same RouterOS API command the live app sends, and the '
          'result is written to the API log. No customer router is changed.\n'
          'این حساب بازبینی است. لیست دستگاه‌های متصل و مسدود، مسدود کردن، '
          'رفع مسدود، تنظیم سرعت، قفل اتصال جدید و وای‌فای روی شبیه‌ساز '
          'همین گوشی انجام می‌شود. هر عمل همان دستور API میکروتیک را ثبت '
          'می‌کند. روتر هیچ مشترکی تغییر نمی‌کند.\n\n'
          'DeltaSIB package data still loads when that service responds.\n'
          'اطلاعات بستهٔ دلتاسیب اگر سرویس جواب بدهد نشان داده می‌شود.\n\n'
          'Continue to use the simulator, or stay here and sign in with a '
          'router account that is on this LAN.\n'
          'برای کار با شبیه‌ساز ادامه دهید، یا همین‌جا بمانید و با یوزر '
          'واقعی روتر همین شبکه وارد شوید.',
        ),
      ),
      actions: [
        if (allowStayOnLogin)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay on login\nماندن در ورود'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue with simulator\nادامه با شبیه‌ساز'),
        ),
      ],
    );
  }
}

class ReviewSimulationBanner extends StatelessWidget {
  const ReviewSimulationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF3A2E12) : const Color(0xFFFFF4D6),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.science_outlined,
                size: 20,
                color: isDark ? const Color(0xFFFFE082) : const Color(0xFF8A5A00),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review simulator — not connected to MikroTik. '
                  'Actions stay on this phone.\n'
                  'شبیه‌ساز بازبینی — به میکروتیک وصل نیست. عملیات روی همین گوشی است.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: isDark ? const Color(0xFFFFE082) : const Color(0xFF5C3B00),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReviewApiLogScreen(),
                    ),
                  );
                },
                child: const Text('API log'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
