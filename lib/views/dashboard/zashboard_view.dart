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
      body: WebViewWidget(controller: _controller),
    );
  }
}
