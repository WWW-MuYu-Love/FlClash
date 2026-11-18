import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Test double for the web view platform: widget tests run without a native
/// implementation, so [WebViewPlatform.instance] must be set to this before
/// pumping a page that builds a [WebViewWidget].
class TestWebViewPlatform extends WebViewPlatform {
  final createdControllers = <TestPlatformWebViewController>[];
  final createdDelegates = <TestPlatformNavigationDelegate>[];

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
    final delegate = TestPlatformNavigationDelegate(params);
    createdDelegates.add(delegate);
    return delegate;
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
  final ranJavaScripts = <String>[];

  /// What [runJavaScriptReturningResult] answers with; `false` by default so
  /// a page that never isolates times out like the real one would.
  Object? javaScriptResult = false;

  PlatformNavigationDelegate? navigationDelegate;

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

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) {
    navigationDelegate = delegate;
    return Future.value();
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) {
    ranJavaScripts.add(javaScript);
    return Future.value(javaScriptResult ?? false);
  }
}

class TestPlatformNavigationDelegate extends PlatformNavigationDelegate {
  TestPlatformNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) {
    this.onPageFinished = onPageFinished;
    return Future.value();
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) {
    this.onWebResourceError = onWebResourceError;
    return Future.value();
  }

  void finishPage(String url) => onPageFinished?.call(url);

  void failResource(WebResourceError error) => onWebResourceError?.call(error);
}

class TestPlatformWebViewWidget extends PlatformWebViewWidget {
  TestPlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class TestPlatformWebViewCookieManager extends PlatformWebViewCookieManager {
  TestPlatformWebViewCookieManager(super.params) : super.implementation();
}
