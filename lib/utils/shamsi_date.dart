/// تبدیل تاریخ میلادی سرور دلتاسیب به خورشیدی افغانستان.
class ShamsiDate {
  const ShamsiDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const monthNames = <String>[
    'حمل',
    'ثور',
    'جوزا',
    'سرطان',
    'اسد',
    'سنبله',
    'میزان',
    'عقرب',
    'قوس',
    'جدی',
    'دلو',
    'حوت',
  ];

  String get monthName => monthNames[month - 1];

  static ShamsiDate fromDateTime(DateTime date) {
    final gy = date.year;
    final gm = date.month;
    final gd = date.day;
    const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    final gy2 = gm > 2 ? gy + 1 : gy;
    var days = 355666 +
        (365 * gy) +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) +
        gd +
        gdm[gm - 1];
    var jy = -1595 + (33 * (days ~/ 12053));
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final jm = days < 186 ? 1 + (days ~/ 31) : 7 + ((days - 186) ~/ 30);
    final jd = 1 + (days < 186 ? (days % 31) : ((days - 186) % 30));
    return ShamsiDate(jy, jm, jd);
  }

  static String label(DateTime? date, {bool withTime = false}) {
    if (date == null) return '—';
    final shamsi = fromDateTime(date);
    final day = faDigits(shamsi.day);
    final text = '$day ${shamsi.monthName}';
    if (!withTime || (date.hour == 0 && date.minute == 0 && date.second == 0)) {
      return text;
    }
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'قبل از ظهر' : 'بعد از ظهر';
    return '$text ساعت ${faDigits(hour12)}:${faDigitsText(minute)} $period';
  }

  static String faDigits(int value) {
    const western = '0123456789';
    const eastern = '۰۱۲۳۴۵۶۷۸۹';
    return '$value'.split('').map((char) {
      final index = western.indexOf(char);
      return index < 0 ? char : eastern[index];
    }).join();
  }

  static String faDigitsText(String value) => value.split('').map((char) {
        const western = '0123456789';
        const eastern = '۰۱۲۳۴۵۶۷۸۹';
        final index = western.indexOf(char);
        return index < 0 ? char : eastern[index];
      }).join();
}
