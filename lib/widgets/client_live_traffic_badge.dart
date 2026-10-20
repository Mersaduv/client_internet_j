import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/client_info.dart';
import '../providers/clients_provider.dart';
import '../utils/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/traffic_instant_display.dart';
import '../utils/traffic_volume_display.dart';

/// Immutable slice for [Selector] — only rebuilds when these values change.
class ClientTrafficUiState {
  final int? rxBps;
  final int? txBps;
  final int? rxBytesTotal;
  final int? txBytesTotal;
  final bool showPlaceholder;
  final bool measured;
  final bool inViewport;

  const ClientTrafficUiState({
    required this.rxBps,
    required this.txBps,
    required this.showPlaceholder,
    required this.measured,
    this.rxBytesTotal,
    this.txBytesTotal,
    this.inViewport = false,
  });

  bool get hasVolume =>
      (rxBytesTotal != null && rxBytesTotal! >= 0) ||
      (txBytesTotal != null && txBytesTotal! >= 0);

  @override
  bool operator ==(Object other) {
    return other is ClientTrafficUiState &&
        other.rxBps == rxBps &&
        other.txBps == txBps &&
        other.rxBytesTotal == rxBytesTotal &&
        other.txBytesTotal == txBytesTotal &&
        other.showPlaceholder == showPlaceholder &&
        other.measured == measured &&
        other.inViewport == inViewport;
  }

  @override
  int get hashCode => Object.hash(
        rxBps,
        txBps,
        rxBytesTotal,
        txBytesTotal,
        showPlaceholder,
        measured,
        inViewport,
      );
}

/// Minimal live-traffic badge for device list rows.
///
/// Uses [Selector] so traffic polling does not rebuild the whole list — only
/// rows whose rates changed are repainted. Per-IP readiness means pending
/// approval devices show traffic as soon as their first sample arrives.
class ClientLiveTrafficBadge extends StatelessWidget {
  ClientLiveTrafficBadge({
    super.key,
    this.client,
    this.ipAddress,
    this.fixedSlot = false,
    this.showVolume = true,
  }) : assert(
          client != null || ipAddress != null,
          'Provide client or ipAddress',
        );

  final ClientInfo? client;
  final String? ipAddress;
  final bool fixedSlot;
  final bool showVolume;

  String? get _ip => client?.ipAddress ?? ipAddress;

  static ClientTrafficUiState _selectState(
    ClientsProvider provider,
    String? ip,
  ) {
    if (ip == null || ip.trim().isEmpty) {
      return const ClientTrafficUiState(
        rxBps: null,
        txBps: null,
        showPlaceholder: false,
        measured: false,
        inViewport: false,
      );
    }

    if (!provider.trafficUiEnabled) {
      return const ClientTrafficUiState(
        rxBps: null,
        txBps: null,
        showPlaceholder: true,
        measured: false,
        inViewport: false,
      );
    }

    final measured = provider.trafficMeasuredForIp(ip);
    final sample = provider.trafficForIp(ip);
    if (measured) {
      return ClientTrafficUiState(
        rxBps: sample?.rxBps ?? 0,
        txBps: sample?.txBps ?? 0,
        rxBytesTotal: sample?.rxBytesTotal,
        txBytesTotal: sample?.txBytesTotal,
        showPlaceholder: false,
        measured: true,
        inViewport: true,
      );
    }

    final timedOut = provider.trafficAwaitingTimedOut(ip);
    return ClientTrafficUiState(
      rxBps: timedOut ? 0 : null,
      txBps: timedOut ? 0 : null,
      showPlaceholder: !timedOut,
      measured: timedOut,
      inViewport: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ip = _ip?.trim();

    if (ip == null || ip.isEmpty) {
      return fixedSlot
          ? const _TrafficSlot(child: _TrafficIdle())
          : const SizedBox.shrink();
    }

    final tick = Provider.of<ClientsProvider>(context, listen: false).trafficDisplayTick;
    return ListenableBuilder(
      listenable: tick,
      builder: (context, _) {
        final state = _selectState(
          Provider.of<ClientsProvider>(context, listen: false),
          ip,
        );
        if (!state.inViewport && !state.measured) {
          return fixedSlot
              ? const _TrafficSlot(child: SizedBox.shrink())
              : const SizedBox.shrink();
        }

        if (state.showPlaceholder) {
          return fixedSlot
              ? const _TrafficSlot(child: _TrafficSkeleton())
              : const _TrafficSkeleton();
        }

        final body = _TrafficBadgeBody(
          rxBps: state.rxBps,
          txBps: state.txBps,
          rxBytesTotal: state.rxBytesTotal,
          txBytesTotal: state.txBytesTotal,
          measured: state.measured,
          showVolume: showVolume,
          emphasize: (state.rxBps ?? 0) > 0 || (state.txBps ?? 0) > 0,
        );

        return fixedSlot ? _TrafficSlot(child: body) : body;
      },
    );
  }
}

class _TrafficBadgeBody extends StatelessWidget {
  const _TrafficBadgeBody({
    required this.rxBps,
    required this.txBps,
    required this.measured,
    required this.emphasize,
    this.rxBytesTotal,
    this.txBytesTotal,
    this.showVolume = true,
  });

  final int? rxBps;
  final int? txBps;
  final int? rxBytesTotal;
  final int? txBytesTotal;
  final bool measured;
  final bool emphasize;
  final bool showVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final downloadColor = emphasize
        ? AppTheme.primaryFor(theme.brightness)
        : colorScheme.onSurface.withValues(alpha: 0.55);
    final uploadColor = colorScheme.onSurface.withValues(alpha: 0.45);
    final volumeColor = colorScheme.onSurface.withValues(alpha: 0.5);
    final bg = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : AppTheme.primaryFor(theme.brightness).withValues(alpha: 0.06);
    final border = colorScheme.outline.withValues(alpha: isDark ? 0.18 : 0.12);
    final hasVolume = showVolume &&
        ((rxBytesTotal != null && rxBytesTotal! >= 0) ||
            (txBytesTotal != null && txBytesTotal! >= 0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RateLine(
            icon: Icons.arrow_downward_rounded,
            color: downloadColor,
            label: TrafficInstantDisplay.compact(rxBps, measured: measured),
            bold: emphasize && (rxBps ?? 0) > 0,
          ),
          const SizedBox(height: 2),
          _RateLine(
            icon: Icons.arrow_upward_rounded,
            color: uploadColor,
            label: TrafficInstantDisplay.compact(txBps, measured: measured),
            bold: emphasize && (txBps ?? 0) > 0,
          ),
          if (hasVolume) ...[
            const SizedBox(height: 3),
            Text(
              TrafficVolumeDisplay.pair(
                rxBytes: rxBytesTotal,
                txBytes: txBytesTotal,
                measured: measured,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.1,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: volumeColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrafficIdle extends StatelessWidget {
  const _TrafficIdle();

  @override
  Widget build(BuildContext context) {
    return const _TrafficBadgeBody(
      rxBps: null,
      txBps: null,
      measured: false,
      emphasize: false,
      showVolume: false,
    );
  }
}

class _TrafficSlot extends StatelessWidget {
  const _TrafficSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: child,
    );
  }
}

class _RateLine extends StatelessWidget {
  const _RateLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.bold,
  });

  final IconData icon;
  final Color color;
  final String label;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        SizedBox(
          width: 76,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrafficSkeleton extends StatelessWidget {
  const _TrafficSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 88,
      height: 34,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

/// Detail screen — live speed badge.
class ClientLiveTrafficDetailRow extends StatelessWidget {
  const ClientLiveTrafficDetailRow({
    super.key,
    this.client,
    required this.ipAddress,
    required this.label,
  });

  final ClientInfo? client;
  final String ipAddress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: theme.brightness == Brightness.dark
                    ? colorScheme.onSurface.withValues(alpha: 0.7)
                    : Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ClientLiveTrafficBadge(
                client: client,
                ipAddress: ipAddress,
                showVolume: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail screen — cumulative usage from the same live poll (no extra API).
class ClientTotalTrafficDetailRow extends StatelessWidget {
  const ClientTotalTrafficDetailRow({
    super.key,
    this.client,
    required this.ipAddress,
    required this.label,
    this.hint,
  });

  final ClientInfo? client;
  final String ipAddress;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ip = (client?.ipAddress ?? ipAddress).trim();

    final tick = Provider.of<ClientsProvider>(context, listen: false).trafficDisplayTick;
    return ListenableBuilder(
      listenable: tick,
      builder: (context, _) {
        final state = ClientLiveTrafficBadge._selectState(
          Provider.of<ClientsProvider>(context, listen: false),
          ip,
        );
        final value = state.hasVolume
            ? TrafficVolumeDisplay.pair(
                rxBytes: state.rxBytesTotal,
                txBytes: state.txBytesTotal,
                measured: state.measured,
              )
            : (state.measured || state.showPlaceholder ? '—' : '—');

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: theme.brightness == Brightness.dark
                            ? colorScheme.onSurface.withValues(alpha: 0.7)
                            : Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              if (hint != null && hint!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 120),
                  child: Text(
                    hint!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Live per-second network total — upload / download split like a status card.
class NetworkTotalTrafficBanner extends StatelessWidget {
  const NetworkTotalTrafficBanner({super.key});

  static const Color _uploadAccent = Color(0xFFE6B422);
  static const Color _downloadAccent = Color(0xFF2EBD59);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final tick = Provider.of<ClientsProvider>(context, listen: false).trafficDisplayTick;
    return ListenableBuilder(
      listenable: tick,
      builder: (context, _) {
        final provider = Provider.of<ClientsProvider>(context, listen: false);
        final agg = provider.aggregateLiveTrafficRate;
        final data = (
          rx: agg.rxBps,
          tx: agg.txBps,
          ready: provider.trafficUiEnabled,
        );
        if (!data.ready) {
          return const SizedBox.shrink();
        }

        final l10n = AppLocalizations.of(context);
        final title =
            l10n?.networkTotalTraffic ?? 'Connected devices usage';
        final uploadLabel = l10n?.upload ?? 'Upload';
        final downloadLabel = l10n?.download ?? 'Download';
        final uploadValue =
            TrafficInstantDisplay.compact(data.tx, measured: true);
        final downloadValue =
            TrafficInstantDisplay.compact(data.rx, measured: true);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: AppTheme.cosmicCardDecoration(
              radius: 16,
              brightness: theme.brightness,
            ),
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _LiveTotalSide(
                        label: uploadLabel,
                        value: uploadValue,
                        accent: _uploadAccent,
                        icon: Icons.arrow_upward_rounded,
                        valueFirst: true,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 44,
                      color: colorScheme.outline.withValues(
                        alpha: isDark ? 0.35 : 0.25,
                      ),
                    ),
                    Expanded(
                      child: _LiveTotalSide(
                        label: downloadLabel,
                        value: downloadValue,
                        accent: _downloadAccent,
                        icon: Icons.arrow_downward_rounded,
                        valueFirst: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveTotalSide extends StatelessWidget {
  const _LiveTotalSide({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
    required this.valueFirst,
  });

  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  final bool valueFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurface,
    );
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final valueBlock = Column(
      crossAxisAlignment:
          valueFirst ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 2),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: valueStyle,
        ),
      ],
    );

    final iconBlock = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Icon(icon, size: 18, color: accent),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: valueFirst
            ? [
                Expanded(child: valueBlock),
                const SizedBox(width: 8),
                iconBlock,
              ]
            : [
                iconBlock,
                const SizedBox(width: 8),
                Expanded(child: valueBlock),
              ],
      ),
    );
  }
}
