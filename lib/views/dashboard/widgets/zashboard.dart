import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/zashboard_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

Uri zashboardUrl(ExternalControllerClient client) {
  final baseUri = client.baseUri;
  return client.secret.isEmpty
      ? baseUri.replace(path: '/ui')
      : baseUri.replace(
          path: '/ui',
          queryParameters: {
            'hostname': baseUri.host,
            'port': '${baseUri.port}',
            'secret': client.secret,
          },
        );
}

/// webview_flutter has no Linux/Windows implementation; those keep the external browser.
@visibleForTesting
bool Function() zashboardInAppWebViewAvailable = () =>
    !system.isLinux && !system.isWindows;

/// Opens the bundled zashboard web panel at 127.0.0.1:9090/ui. 9090 is
/// bound by the extension core only, so the panel only works while the
/// VPN is running; with the tunnel down the card stays dimmed and the
/// tap does nothing.
class ZashboardCard extends ConsumerWidget {
  const ZashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnRunning = ref.watch(runningVpnOptionsProvider)?.enable == true;
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    return DashboardCard(
      semanticLabel: 'Zashboard',
      onTap: vpnRunning
          ? () {
              ref.read(setupActionProvider.notifier).ensureIOSController();
              final client = ref.read(externalControllerClientProvider);
              if (client.unauthorized) {
                dialogs.showBanner(
                  context.appLocalizations.externalControllerSecretMismatch,
                  level: BannerLevel.error,
                );
                return;
              }
              final url = zashboardUrl(client);
              if (zashboardInAppWebViewAvailable()) {
                unawaited(openZashboard(context, url));
              } else {
                unawaited(launchUrl(url));
              }
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dashboard,
            title: 'Zashboard',
            trailing: [
              GlyphIcon(
                AppGlyphs.openExternal,
                size: 18,
                color: vpnRunning
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '127.0.0.1:9090/ui',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              color: vpnRunning
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
