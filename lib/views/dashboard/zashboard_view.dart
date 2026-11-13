import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ZashboardView extends StatefulWidget {
  const ZashboardView({super.key, required this.url});

  final Uri url;

  @override
  State<ZashboardView> createState() => _ZashboardViewState();
}

class _ZashboardViewState extends State<ZashboardView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: 'Zashboard',
      // A web view ignores the MediaQuery top padding, so offset it below the bar.
      body: Padding(
        padding: EdgeInsets.only(top: context.appBarInset),
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}

/// No drag-back: a swipe inside the web view must never pop the page.
class ZashboardRoute<T> extends CardPageRoute<T> {
  ZashboardRoute({required super.builder});

  @override
  bool get popGestureEnabled => false;
}

Future<T?> openZashboard<T>(BuildContext context, Uri url) {
  if (context.isMobileView) {
    return Navigator.of(
      context,
    ).push<T>(ZashboardRoute<T>(builder: (_) => ZashboardView(url: url)));
  }
  return showExtend<T>(
    context,
    props: const ExtendProps(forceFull: true),
    builder: (_) => ZashboardView(url: url),
  );
}
