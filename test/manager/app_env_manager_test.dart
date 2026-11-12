import 'package:fl_clash/manager/app_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    globalState.appEnv = 'stable';
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool safeMode,
    bool showEnvBanner = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          safeModeProvider.overrideWithValue(safeMode),
          appSettingProvider.overrideWithBuild(
            (_, _) => AppSettingProps(showEnvBanner: showEnvBanner),
          ),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AppEnvManager(child: SizedBox(key: Key('child'))),
        ),
      ),
    );
  }

  testWidgets('a stable build carries no banner', (tester) async {
    await pump(tester, safeMode: false);

    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(find.byType(Banner), findsNothing);
  });

  testWidgets('a pre build is bannered while the watermark is on', (
    tester,
  ) async {
    globalState.appEnv = 'pre';
    addTearDown(() => globalState.appEnv = 'stable');
    await pump(tester, safeMode: false);

    final banner = tester.widget<Banner>(find.byType(Banner));
    // Tests run in debug mode, so a pre build reports DEBUG, not PRE.
    expect(banner.message, 'DEBUG');
    expect(find.byKey(const Key('child')), findsOneWidget);
  });

  testWidgets('turning the watermark off hides the pre banner', (tester) async {
    globalState.appEnv = 'pre';
    addTearDown(() => globalState.appEnv = 'stable');
    await pump(tester, safeMode: false, showEnvBanner: false);

    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(find.byType(Banner), findsNothing);
  });

  testWidgets('a safe mode build is bannered on any channel', (tester) async {
    await pump(tester, safeMode: true);

    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'SAFE MODE');
    expect(find.byKey(const Key('child')), findsOneWidget);
  });

  testWidgets('a safe mode build stays bannered with the watermark off', (
    tester,
  ) async {
    await pump(tester, safeMode: true, showEnvBanner: false);

    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'SAFE MODE');
    expect(find.byKey(const Key('child')), findsOneWidget);
  });
}
