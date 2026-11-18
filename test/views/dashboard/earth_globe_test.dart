import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/widget_registry.dart';
import 'package:fl_clash/views/dashboard/widgets/earth_globe.dart';
import 'package:fl_clash/views/dashboard/widgets/zashboard.dart';
import 'package:fl_clash/views/dashboard/zashboard_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_webview_platform.dart';

const _size = Size(400, 800);

const _runningOptions = VpnOptions(
  enable: true,
  port: 7890,
  ipv6: false,
  dnsHijacking: false,
  accessControlProps: AccessControlProps(
    enable: false,
    mode: AccessControlMode.acceptSelected,
    acceptList: [],
    rejectList: [],
  ),
  allowBypass: false,
  systemProxy: true,
  bypassDomain: [],
  stack: 'mixed',
);

VpnOptions _options({required bool enable}) =>
    _runningOptions.copyWith(enable: enable);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late TestWebViewPlatform webViewPlatform;
  late ExternalControllerClient client;

  setUp(() {
    client = ExternalControllerClient(
      baseUri: Uri.parse('http://127.0.0.1:9090'),
      secret: 'test-secret',
    );
    container = ProviderContainer(
      overrides: [externalControllerClientProvider.overrideWithValue(client)],
    );
    globalState.container = container;
    webViewPlatform = TestWebViewPlatform();
    WebViewPlatform.instance = webViewPlatform;
  });

  tearDown(() {
    client.close();
    container.dispose();
  });

  void enableWebView() {
    final defaultAvailable = zashboardInAppWebViewAvailable;
    zashboardInAppWebViewAvailable = () => true;
    addTearDown(() => zashboardInAppWebViewAvailable = defaultAvailable);
  }

  Future<void> pumpCard(WidgetTester tester) async {
    container.read(viewSizeProvider.notifier).value = _size;
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: HostScaffold(body: EarthGlobeCard())),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> teardownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  void setTunnel({required bool enable}) {
    container.read(runningVpnOptionsProvider.notifier).state = _options(
      enable: enable,
    );
  }

  TestPlatformWebViewController webViewController() =>
      webViewPlatform.createdControllers.single;

  void finishPage() {
    webViewPlatform.createdDelegates.single.finishPage(
      zashboardUrl(client).toString(),
    );
  }

  testWidgets('tunnel off shows the title and no web view', (tester) async {
    enableWebView();

    await pumpCard(tester);

    expect(find.text('Global connections'), findsOneWidget);
    expect(find.text('Live globe of current connections'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(
      webViewPlatform.createdControllers.expand((c) => c.loadedUris),
      isEmpty,
    );

    await teardownWidget(tester);
  });

  testWidgets('tunnel on loads the zashboard page and shows a spinner', (
    tester,
  ) async {
    enableWebView();
    setTunnel(enable: true);

    await pumpCard(tester);

    expect(find.text('Global connections'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(find.byType(ActivityIndicator), findsOneWidget);
    expect(webViewPlatform.createdControllers, hasLength(1));
    expect(webViewPlatform.createdControllers.single.loadedUris, [
      zashboardUrl(client),
    ]);

    await teardownWidget(tester);
  });

  testWidgets('secret mismatch shows the mismatch state and loads nothing', (
    tester,
  ) async {
    enableWebView();
    client.unauthorized = true;
    setTunnel(enable: true);

    await pumpCard(tester);

    expect(
      find.text(
        'The controller secret is out of sync. Restart the tunnel to sync it again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open full Zashboard'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(
      webViewPlatform.createdControllers.expand((c) => c.loadedUris),
      isEmpty,
    );

    await teardownWidget(tester);
  });

  testWidgets('the globe loads again once the secret is back in sync', (
    tester,
  ) async {
    enableWebView();
    client.unauthorized = true;
    setTunnel(enable: true);

    await pumpCard(tester);
    expect(
      find.text(
        'The controller secret is out of sync. Restart the tunnel to sync it again.',
      ),
      findsOneWidget,
    );

    client.unauthorized = false;
    setTunnel(enable: false);
    await tester.pump();
    setTunnel(enable: true);
    await tester.pump();

    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(webViewPlatform.createdControllers.single.loadedUris, hasLength(1));

    await teardownWidget(tester);
  });

  testWidgets('the spinner clears once the globe is isolated', (tester) async {
    enableWebView();
    setTunnel(enable: true);

    await pumpCard(tester);
    webViewController().javaScriptResult = true;
    finishPage();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(find.byType(ActivityIndicator), findsNothing);
    expect(webViewController().ranJavaScripts, hasLength(1));
    expect(
      webViewController().ranJavaScripts.single,
      contains('earth-globe-card'),
    );

    await teardownWidget(tester);
  });

  testWidgets('a page that never isolates shows the failed state', (
    tester,
  ) async {
    enableWebView();
    setTunnel(enable: true);

    await pumpCard(tester);
    finishPage();
    await tester.pump(const Duration(seconds: 31));

    expect(find.text('The globe could not be loaded.'), findsOneWidget);
    expect(find.text('Open full Zashboard'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);

    await teardownWidget(tester);
  });

  testWidgets('a main-frame resource error shows the failed state', (
    tester,
  ) async {
    enableWebView();
    setTunnel(enable: true);

    await pumpCard(tester);
    webViewPlatform.createdDelegates.single.failResource(
      const WebResourceError(
        errorCode: -1,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: true,
      ),
    );
    await tester.pump();

    expect(find.text('The globe could not be loaded.'), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('a sub-resource error keeps the globe loading', (tester) async {
    enableWebView();
    setTunnel(enable: true);

    await pumpCard(tester);
    webViewPlatform.createdDelegates.single.failResource(
      const WebResourceError(
        errorCode: -1,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: false,
      ),
    );
    await tester.pump();

    expect(find.text('The globe could not be loaded.'), findsNothing);
    expect(find.byType(ActivityIndicator), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('only the off-to-on transition reloads the page', (tester) async {
    enableWebView();

    await pumpCard(tester);
    expect(
      webViewPlatform.createdControllers.expand((c) => c.loadedUris),
      isEmpty,
    );

    setTunnel(enable: true);
    await tester.pump();
    expect(webViewPlatform.createdControllers.single.loadedUris, hasLength(1));

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(webViewPlatform.createdControllers.single.loadedUris, hasLength(1));

    setTunnel(enable: false);
    await tester.pump();
    setTunnel(enable: true);
    await tester.pump();
    expect(webViewPlatform.createdControllers.single.loadedUris, hasLength(2));

    await teardownWidget(tester);
  });

  testWidgets('header tap opens the full zashboard', (tester) async {
    enableWebView();
    setTunnel(enable: true);

    await pumpCard(tester);
    await tester.tap(find.text('Global connections'));
    await tester.pumpAndSettle();

    expect(find.byType(ZashboardView), findsOneWidget);

    await teardownWidget(tester);
  });

  testWidgets('without an in-app web view the header opens the browser', (
    tester,
  ) async {
    setTunnel(enable: true);
    final launchedUrls = <String>[];
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
          if (call.method == 'launch') {
            launchedUrls.add((call.arguments as Map)['url'] as String);
            return true;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcherChannel, null),
    );

    await pumpCard(tester);

    expect(find.text('Global connections'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(webViewPlatform.createdControllers, isEmpty);

    await tester.tap(find.text('Global connections'));
    await tester.pump();

    expect(launchedUrls, [zashboardUrl(client).toString()]);

    await teardownWidget(tester);
  });

  testWidgets('the card is registered with its label and description', (
    tester,
  ) async {
    await pumpCard(tester);

    const widget = DashboardWidget.earthGlobe;
    expect(widget.card, isA<EarthGlobeCard>());
    expect(
      widget.label(tester.element(find.byType(EarthGlobeCard))),
      isNotEmpty,
    );
    expect(
      widget.description(tester.element(find.byType(EarthGlobeCard))),
      isNotEmpty,
    );

    await teardownWidget(tester);
  });
}
