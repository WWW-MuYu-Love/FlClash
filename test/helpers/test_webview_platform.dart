import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Test double for the web view platform: widget tests run without a native
/// implementation, so [WebViewPlatform.instance] must be set to this before
/// pumping a page that builds a [WebViewWidget].
class TestWebViewPlatform extends WebViewPlatform {
  final createdControllers = <TestPlatformWebViewController>[];

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return TestPlatformWebViewCookieManager(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = TestPlatformWebViewController(params);
    createdControllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return TestPlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return TestPlatformWebViewWidget(params);
  }
}

class TestPlatformWebViewController extends PlatformWebViewController {
  TestPlatformWebViewController(super.params) : super.implementation();

  final loadedUris = <Uri>[];
  final javaScriptModes = <JavaScriptMode>[];

  @override
  Future<void> loadRequest(LoadRequestParams params) {
    loadedUris.add(params.uri);
    return Future.value();
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) {
    javaScriptModes.add(javaScriptMode);
    return Future.value();
  }
}

class TestPlatformNavigationDelegate extends PlatformNavigationDelegate {
  TestPlatformNavigationDelegate(super.params) : super.implementation();
}

class TestPlatformWebViewWidget extends PlatformWebViewWidget {
  TestPlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class TestPlatformWebViewCookieManager extends PlatformWebViewCookieManager {
  TestPlatformWebViewCookieManager(super.params) : super.implementation();
}
