import 'package:flutter/material.dart';

import '../data/internet_packages_data.dart';
import '../utils/app_theme.dart';

/// مودال یک‌بارهٔ انتخاب ولایت برای صفحهٔ ورود.
Future<PackageProvince?> showLoginProvinceDialog(
  BuildContext context, {
  PackageProvince? selected,
}) {
  final isEnglish = Localizations.localeOf(context).languageCode == 'en';
  return showGeneralDialog<PackageProvince>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'province',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondary) {
      return SafeArea(
        child: Center(
          child: _LoginProvinceCard(
            isEnglish: isEnglish,
            selected: selected,
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
          child: child,
        ),
      );
    },
  );
}

class _LoginProvinceCard extends StatelessWidget {
  const _LoginProvinceCard({
    required this.isEnglish,
    required this.selected,
  });

  final bool isEnglish;
  final PackageProvince? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: isDark ? const Color(0xFF121826) : Colors.white,
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 28,
                  color: isDark ? AppTheme.darkGlow : AppTheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  isEnglish ? 'Choose your province' : 'ولایت خود را انتخاب کنید',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isEnglish
                      ? 'Chosen once and used for sign-in.'
                      : 'فقط یک بار انتخاب می‌شود و برای ورود استفاده می‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                for (final province in PackageProvince.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ProvinceChoice(
                      label: province.title(isEnglish),
                      selected: selected == province,
                      isDark: isDark,
                      onTap: () => Navigator.of(context).pop(province),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProvinceChoice extends StatelessWidget {
  const _ProvinceChoice({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppTheme.darkGlow : AppTheme.primary;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : (isDark ? const Color(0xFF1B2433) : const Color(0xFFF4F7FB)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// دیالوگ انتخاب ولایت — برای بسته‌ها و سرویس اینترنت مشترک است.
class ProvincePickerOverlay extends StatelessWidget {
  const ProvincePickerOverlay({
    super.key,
    required this.isEnglish,
    required this.requiredChoice,
    required this.selected,
    required this.onSelected,
    this.onDismiss,
    this.subtitleFa,
    this.subtitleEn,
  });

  final bool isEnglish;
  final bool requiredChoice;
  final PackageProvince? selected;
  final ValueChanged<PackageProvince> onSelected;
  final VoidCallback? onDismiss;
  final String? subtitleFa;
  final String? subtitleEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subtitle = isEnglish
        ? (subtitleEn ??
            'Packages differ by province. Your choice will be saved as default.')
        : (subtitleFa ??
            'بسته‌ها بر اساس ولایت متفاوت‌اند. انتخاب شما به‌عنوان پیش‌فرض ذخیره می‌شود.');

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DecoratedBox(
                decoration: AppTheme.cosmicCardDecoration(
                  radius: 24,
                  brightness: theme.brightness,
                  withGlow: true,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isEnglish
                            ? 'Select your province'
                            : 'ولایت خود را انتخاب کنید',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final province in PackageProvince.values) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => onSelected(province),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: selected == province
                                      ? (isDark
                                            ? AppTheme.darkAction
                                            : AppTheme.primary
                                                .withValues(alpha: 0.1))
                                      : (isDark
                                            ? AppTheme.darkCardBottom
                                                .withValues(alpha: 0.65)
                                            : Colors.white),
                                  border: Border.all(
                                    color: selected == province
                                        ? (isDark
                                              ? AppTheme.darkGlow
                                              : AppTheme.primary)
                                        : (isDark
                                              ? AppTheme.darkRim
                                                  .withValues(alpha: 0.4)
                                              : AppTheme.lightRim),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      color: selected == province
                                          ? (isDark
                                                ? AppTheme.darkActionForeground
                                                : AppTheme.primary)
                                          : (isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.primary),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        province.title(isEnglish),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: selected == province && isDark
                                              ? AppTheme.darkActionForeground
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (selected == province)
                                      Icon(
                                        Icons.check_circle,
                                        color: isDark
                                            ? AppTheme.darkActionForeground
                                            : AppTheme.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!requiredChoice && onDismiss != null)
                        TextButton(
                          onPressed: onDismiss,
                          child: Text(isEnglish ? 'Close' : 'بستن'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// دراپ‌داون جمع‌وجور ولایت برای هدر / نوار عنوان
class ProvinceDropdown extends StatelessWidget {
  const ProvinceDropdown({
    super.key,
    required this.value,
    required this.isEnglish,
    required this.onChanged,
    this.compact = false,
  });

  final PackageProvince value;
  final bool isEnglish;
  final ValueChanged<PackageProvince> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: AppTheme.cosmicCardDecoration(
        radius: 14,
        brightness: theme.brightness,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PackageProvince>(
          value: value,
          isDense: compact,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: isDark ? AppTheme.darkSurface : AppTheme.pureWhite,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.primary,
          ),
          padding: EdgeInsetsDirectional.only(
            start: compact ? 10 : 12,
            end: compact ? 4 : 8,
          ),
          items: PackageProvince.values
              .map(
                (p) => DropdownMenuItem(
                  value: p,
                  child: Text(
                    p.title(isEnglish),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: compact ? 13.5 : 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}
