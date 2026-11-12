import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The bundled zashboard panel in an in-app web view, so the controller secret in its URL never reaches the external browser; the page shows no address bar.
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
      // A web view ignores the MediaQuery top padding the floating bar
      // gives the body, so its top would sit under the bar: offset it
      // explicitly to where the bar ends.
      body: Padding(
        padding: EdgeInsets.only(top: context.appBarInset),
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}

/// A web view owns its own horizontal gestures, so the page carries no
/// drag-back: a swipe inside zashboard must never pop the page. The bar's
/// back button still pops it.
class ZashboardRoute<T> extends CardPageRoute<T> {
  ZashboardRoute({required super.builder});

  @override
  bool get popGestureEnabled => false;
}

/// Opens the bundled zashboard panel: a full page on mobile, a side sheet
/// elsewhere.
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
