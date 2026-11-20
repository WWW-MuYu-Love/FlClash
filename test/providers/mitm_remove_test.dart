import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/providers/mitm.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' show join;

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

void main() {
  test('remove deletes CA files and returns true', () async {
    final root = Directory.systemTemp.createTempSync('mitm_remove');
    addTearDown(() => root.deleteSync(recursive: true));
    await useAppPaths(root);
    final cert = File(join(root.path, 'mitm', 'ca.crt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('cert');
    final key = File(join(root.path, 'mitm', 'ca.key'))
      ..createSync(recursive: true)
      ..writeAsStringSync('key');
    final certBak = File(join(root.path, 'mitm', 'ca.crt.bak'))
      ..createSync(recursive: true)
      ..writeAsStringSync('cert bak');
    final keyBak = File(join(root.path, 'mitm', 'ca.key.bak'))
      ..createSync(recursive: true)
      ..writeAsStringSync('key bak');
    final core = _MockCore();
    when(() => core.getMitmCertificate()).thenAnswer((_) async => null);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        mitmTrustStoreProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    final removed = await container
        .read(mitmTrustStateProvider.notifier)
        .remove()
        .timeout(const Duration(seconds: 5));

    expect(removed, isTrue);
    expect(await cert.exists(), isFalse);
    expect(await key.exists(), isFalse);
    expect(await certBak.exists(), isFalse);
    expect(await keyBak.exists(), isFalse);

    final again = await container
        .read(mitmTrustStateProvider.notifier)
        .remove()
        .timeout(const Duration(seconds: 5));
    expect(again, isTrue);
  });
}
