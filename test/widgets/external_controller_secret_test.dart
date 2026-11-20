import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _secretLabel = 'External controller secret';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpGeneralView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1000, 3000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: GeneralView()),
      ),
    );
    await tester.pumpAndSettle();
  }

  void setSecret(String secret) {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(secret: secret));
  }

  Future<void> submitSecret(WidgetTester tester, String text) async {
    await tester.tap(find.text(_secretLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), text);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
  }

  testWidgets('the secret row is always visible, with no toggle to open', (
    tester,
  ) async {
    await pumpGeneralView(tester);

    expect(find.text(_secretLabel), findsOneWidget);
    expect(find.widgetWithText(ListRow, 'External controller'), findsNothing);
  });

  testWidgets('the row shows the stored secret', (tester) async {
    await pumpGeneralView(tester);
    setSecret('first-secret');
    await tester.pumpAndSettle();

    expect(find.text('first-secret'), findsOneWidget);
  });

  testWidgets('a secret typed into the row replaces the stored one', (
    tester,
  ) async {
    await pumpGeneralView(tester);
    setSecret('first-secret');
    await tester.pumpAndSettle();

    await submitSecret(tester, '  my-own-secret ');

    expect(container.read(patchClashConfigProvider).secret, 'my-own-secret');
  });

  testWidgets('the row refuses an empty secret', (tester) async {
    await pumpGeneralView(tester);
    setSecret('first-secret');
    await tester.pumpAndSettle();

    await submitSecret(tester, '   ');

    expect(container.read(patchClashConfigProvider).secret, 'first-secret');
  });
}
