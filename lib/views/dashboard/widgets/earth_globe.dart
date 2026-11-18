import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/widgets/zashboard.dart';
import 'package:fl_clash/views/dashboard/zashboard_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EarthGlobeCard extends ConsumerStatefulWidget {
  const EarthGlobeCard({super.key});

  @override
  ConsumerState<EarthGlobeCard> createState() => _EarthGlobeCardState();
}

class _EarthGlobeCardState extends ConsumerState<EarthGlobeCard> {
  static const _webViewHeight = 380.0;
  static const _pollInterval = Duration(milliseconds: 500);
  static const _maxPollAttempts = 60;

  // Cropping depends on Zashboard's DOM structure, so a Zashboard upgrade
  // can break it.
  static const _isolateScript = r'''
(() => {
  const titles = ['Global connections', 'Глобальные подключения', '全球连接', '全球連接'];
  let card = document.querySelector('.earth-globe-card');
  if (!card) {
    for (const el of document.querySelectorAll('div, span, h1, h2, h3, p')) {
      if (el.children.length === 0 && titles.includes(el.textContent.trim())) {
        let node = el;
        while (node && !node.querySelector('canvas')) node = node.parentElement;
        card = node;
        break;
      }
    }
  }
  if (!card || !card.querySelector('canvas')) return false;
  card.style.width = '100%';
  card.style.gridColumn = '1 / -1';
  const globe = card.querySelector('.h-96');
  if (globe) globe.style.height = 'calc(100vh - 72px)';
  let node = card;
  while (node && node !== document.body) {
    const parent = node.parentElement;
    if (!parent) break;
    for (const child of parent.children) {
      if (child !== node) child.style.display = 'none';
    }
    node = parent;
  }
  document.body.style.margin = '0';
  return true;
})()
''';

  WebViewController? _controller;
  Timer? _pollTimer;
  var _pollAttempts = 0;
  var _isolated = false;
  var _failed = false;
  var _unauthorized = false;

  @override
  void initState() {
    super.initState();
    if (!zashboardInAppWebViewAvailable()) {
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _startIsolation(),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _stopPolling();
              if (mounted) {
                setState(() => _failed = true);
              }
            }
          },
        ),
      );
    if (ref.read(runningVpnOptionsProvider)?.enable == true) {
      _load();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _load() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _stopPolling();
    // unauthorized is a snapshot: the client only learns it when a request
    // already got a 401, so this blocks loading a globe that would stay empty.
    if (ref.read(externalControllerClientProvider).unauthorized) {
      _failed = true;
      _unauthorized = true;
      return;
    }
    unawaited(
      controller.loadRequest(
        zashboardUrl(ref.read(externalControllerClientProvider)),
      ),
    );
  }

  void _startIsolation() {
    if (_pollTimer != null || _isolated || _failed) {
      return;
    }
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    final controller = _controller;
    if (controller == null || _isolated || _failed) {
      _stopPolling();
      return;
    }
    var isolated = false;
    try {
      isolated =
          await controller.runJavaScriptReturningResult(_isolateScript) == true;
    } catch (_) {
      isolated = false;
    }
    if (!mounted) {
      return;
    }
    if (isolated) {
      _stopPolling();
      setState(() => _isolated = true);
      return;
    }
    _pollAttempts += 1;
    if (_pollAttempts >= _maxPollAttempts) {
      _stopPolling();
      setState(() => _failed = true);
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _openFull() {
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

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final vpnRunning = ref.watch(runningVpnOptionsProvider)?.enable == true;
    ref.listen(runningVpnOptionsProvider, (previous, next) {
      if (previous?.enable != true && next?.enable == true) {
        setState(() {
          _failed = false;
          _isolated = false;
          _unauthorized = false;
        });
        _load();
      }
    });
    return DashboardCard(
      semanticLabel: appLocalizations.earthGlobe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: vpnRunning ? 1 : 0.4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: vpnRunning ? _openFull : null,
              child: DashboardCardHeader(
                glyph: AppGlyphs.locate,
                title: appLocalizations.earthGlobe,
                chevron: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildBody(context, vpnRunning: vpnRunning),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool vpnRunning}) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final controller = _controller;
    if (!vpnRunning ||
        !zashboardInAppWebViewAvailable() ||
        controller == null) {
      return Text(
        appLocalizations.earthGlobeDesc,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote
            .of(context, emphasized: true)
            .copyWith(
              color: colorScheme.onSurfaceVariant.withValues(
                alpha: vpnRunning ? 1 : 0.6,
              ),
            ),
      );
    }
    if (_failed) {
      return SizedBox(
        height: _webViewHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _unauthorized
                  ? appLocalizations.externalControllerSecretMismatch
                  : appLocalizations.earthGlobeLoadFailed,
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote.of(context, emphasized: true),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _openFull,
              child: Text(appLocalizations.earthGlobeOpenFull),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: _webViewHeight,
      child: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (!_isolated) const Center(child: ActivityIndicator(size: 24)),
        ],
      ),
    );
  }
}
