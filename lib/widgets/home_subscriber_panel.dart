import 'dart:async';

import 'package:flutter/material.dart';

import '../data/internet_packages_data.dart';
import '../models/internet_package.dart';
import '../services/settings_service.dart';
import '../services/sib_package_store.dart';
import '../utils/main_navigation.dart';
import '../utils/shamsi_date.dart';
import '../utils/sib_package_insight.dart';
import '../utils/app_theme.dart';
import 'sib_package_card.dart';

/// سرصفحهٔ مشترک: بستهٔ واقعی، شمار دستگاه‌ها و بسته‌های همان ولایت.
class HomeSubscriberPanel extends StatefulWidget {
  const HomeSubscriberPanel({
    super.key,
    required this.connectedCount,
    required this.limitedCount,
    required this.onOpenConnected,
    required this.onOpenLimited,
  });

  final int connectedCount;
  final int limitedCount;
  final VoidCallback onOpenConnected;
  final VoidCallback onOpenLimited;

  @override
  State<HomeSubscriberPanel> createState() => _HomeSubscriberPanelState();
}

class _HomeSubscriberPanelState extends State<HomeSubscriberPanel> {
  final _settings = SettingsService();
  SibPackageInsight? _insight = SibPackageStore.snapshot;
  List<InternetPackage> _popular = const [];
  bool _loadingPackage = SibPackageStore.snapshot == null;

  @override
  void initState() {
    super.initState();
    SibPackageStore.listenable.addListener(_onPackage);
    _loadPackages();
    unawaited(SibPackageStore.refresh().whenComplete(_onPackage));
  }

  @override
  void dispose() {
    SibPackageStore.listenable.removeListener(_onPackage);
    super.dispose();
  }

  void _onPackage() {
    if (!mounted) return;
    setState(() {
      _insight = SibPackageStore.snapshot;
      _loadingPackage = false;
    });
  }

  Future<void> _loadPackages() async {
    final provinceId = await _settings.getPackageProvinceId();
    final province = PackageProvinceX.tryParse(provinceId) ?? PackageProvince.herat;
    final catalog = InternetPackagesData.catalogFor(province);
    final popular = _mix(catalog);
    if (mounted) setState(() => _popular = popular);
  }

  List<InternetPackage> _mix(ProvincePackageCatalog catalog) {
    final groups = [catalog.unlimited, catalog.dedicated, catalog.volume];
    final mixed = <InternetPackage>[];
    var round = 0;
    while (mixed.length < 9) {
      var added = false;
      for (final group in groups) {
        if (round < group.length) {
          mixed.add(group[round]);
          added = true;
        }
      }
      if (!added) break;
      round++;
    }
    return mixed;
  }

  @override
  Widget build(BuildContext context) {
    final greeting = SibPackageInsight.greetingLine(
      SibPackageStore.displayName ?? _insight?.customerName,
    );
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 360;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : AppTheme.primary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 12 : 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              greeting,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: compact ? 20 : 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            if (_loadingPackage)
              const SibPackageCardSkeleton()
            else if (_insight != null)
              SibPackageCard(insight: _insight!)
            else
              const _EmptyPackage(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'متصل به اینترنت',
                    value: '${ShamsiDate.faDigits(widget.connectedCount)} دستگاه',
                    icon: Icons.hub_outlined,
                    onTap: widget.onOpenConnected,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    title: 'دستگاه های محدود شده',
                    value: '${ShamsiDate.faDigits(widget.limitedCount)} دستگاه',
                    icon: Icons.desktop_access_disabled_outlined,
                    onTap: widget.onOpenLimited,
                  ),
                ),
              ],
            ),
            if (_popular.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'بسته های پر طرفدار',
                style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: compact ? 214 : 228,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _popular.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    return _PopularCard(
                      package: _popular[index],
                      width: compact ? 158 : 176,
                      onTap: () => mainBottomTabRequest.value = 1,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyPackage extends StatelessWidget {
  const _EmptyPackage();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : const Color(0xFF5C6B7A);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101C2E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white12 : AppTheme.lightRim),
      ),
      child: Text(
        'حجم هنوز نمایش داده نشده. در صفحهٔ ورود، کد پشتیبانی را یک‌بار وارد کنید.',
        textAlign: TextAlign.right,
        style: TextStyle(color: muted),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : AppTheme.primary;
    final muted = isDark ? Colors.white70 : const Color(0xFF5C6B7A);
    return Material(
      color: isDark ? const Color(0xFF10182A) : Colors.white,
      elevation: isDark ? 0 : 1,
      shadowColor: AppTheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isDark ? Colors.white12 : AppTheme.lightRim),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, compact ? 12 : 14, 10, compact ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: isDark ? Colors.white24 : AppTheme.lightRim),
                ),
                child: Icon(icon, color: ink, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: compact ? 12 : 13, height: 1.3),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularCard extends StatelessWidget {
  const _PopularCard({
    required this.package,
    required this.onTap,
    required this.width,
  });

  final InternetPackage package;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : AppTheme.primary;
    final muted = isDark ? Colors.white70 : const Color(0xFF5C6B7A);
    final badge = package.isUnlimited
        ? 'بسته نامحدود'
        : package.isVolume
            ? 'بسته حجمی'
            : 'بسته اختصاصی';
    final days = package.durationMonths * 30;
    return SizedBox(
      width: width,
      child: Material(
        color: isDark ? const Color(0xFF10182A) : Colors.white,
        elevation: isDark ? 0 : 1,
        shadowColor: AppTheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? Colors.white12 : AppTheme.lightRim),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  package.heroLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const Spacer(),
                _line(Icons.wifi, package.speedLabel, muted),
                const SizedBox(height: 6),
                _line(Icons.calendar_today_outlined, '$days Days', muted),
                const SizedBox(height: 6),
                _line(Icons.payments_outlined, package.priceLabel, muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, Color muted) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        const SizedBox(width: 6),
        Icon(icon, color: muted, size: 14),
      ],
    );
  }
}

