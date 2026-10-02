import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../l10n/s.dart';
import '../../../services/network/vpn_bypass_service.dart';

import 'package:m3e_ui/m3e_ui.dart';

class VpnBypassCard extends StatelessWidget {
  const VpnBypassCard({super.key});

  @override
  Widget build(BuildContext context) {
    final service = VpnBypassService.instance;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        service.enabledNotifier,
        service.statusNotifier,
      ]),
      builder: (context, _) {
        final status = service.status;
        final enabled = service.enabled;

        return SegmentedCardGroup(
          children: [
            SwitchListTile(
              title: Text(context.l10n.vpnBypass_title),
              subtitle: Text(_subtitle(context, status)),
              secondary: Icon(
                Symbols.route_rounded,
                fill: status.bound ? 1 : 0,
                color: status.bound ? theme.colorScheme.primary : null,
              ),
              value: enabled,
              onChanged: service.setEnabled,
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      status.bound
                          ? Symbols.check_circle_rounded
                          : Symbols.info_rounded,
                      size: 18,
                      color: status.bound
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.vpnBypass_disclaimer,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _subtitle(BuildContext context, VpnBypassStatus status) {
    if (!status.enabled) {
      return context.l10n.vpnBypass_subtitle;
    }

    switch (status.reason) {
      case 'bound':
        final transport = _transportLabel(context, status.transport);
        return '$transport · ${context.l10n.vpnBypass_bound}';
      case 'waitingForVpn':
        return context.l10n.vpnBypass_waitingForVpn;
      case 'noNonVpnNetwork':
        return context.l10n.vpnBypass_noNetwork;
      case 'bindFailed':
        return context.l10n.vpnBypass_bindFailed;
      case 'unsupported':
        return context.l10n.vpnBypass_unsupported;
      case 'enumerationFailed':
      case 'nativeError':
      case 'invalidStatus':
        return context.l10n.vpnBypass_error;
      default:
        return status.bound
            ? context.l10n.vpnBypass_bound
            : context.l10n.vpnBypass_subtitle;
    }
  }

  String _transportLabel(BuildContext context, String transport) {
    return switch (transport) {
      'wifi' => context.l10n.vpnBypass_transportWifi,
      'ethernet' => context.l10n.vpnBypass_transportEthernet,
      'cellular' => context.l10n.vpnBypass_transportCellular,
      _ => context.l10n.vpnBypass_transportOther,
    };
  }
}
