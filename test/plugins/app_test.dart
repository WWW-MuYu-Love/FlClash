import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/app');

  setUp(() {
    App().clearPackageIconCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    App().clearPackageIconCache();
  });

  test('has no app plugin off Android', () {
    expect(app, isNull);
  });

  test('a failed install is anything but success or abort', () {
    expect(packageInstallFailed(0), isFalse);
    expect(packageInstallFailed(3), isFalse);
    expect(packageInstallFailed(1), isTrue);
  });

  test('exposes network changes as a stream', () {
    expect(App().networkChanges, isNotNull);
  });

  test('watches the network while the stream is listened to', () async {
    final watched = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          watched.add(call.arguments as bool);
          return true;
        });

    final subscription = App().networkChanges.listen((_) {});
    await pumpEventQueue();
    await subscription.cancel();
    await pumpEventQueue();

    expect(watched, [true, false]);
  });

  test('reads the device info Android answers with', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'sdkInt': 34, 'isTelevision': false},
        );

    expect(await App().getDeviceInfo(), (sdkInt: 34, isTelevision: false));
  });

  test('forwards the simple platform calls and their answers', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return switch (call.method) {
            'moveTaskToBack' => true,
            'tip' => true,
            'initShortcuts' => true,
            'updateExcludeFromRecents' => true,
            'extractAsset' => true,
            'clearDownloads' => true,
            'installPackage' => 0,
            'hasRootAccess' => true,
            'removeCaCertificateWithRoot' => true,
            'openCertificateSettings' => true,
            'getChinaPackageNames' => '["com.a","com.b"]',
            'requestLocalNetworkPermission' => true,
            'getPackages' =>
              '[{"packageName":"com.a","label":"A","system":false,'
                  '"internet":true,"lastUpdateTime":0}]',
            _ => null,
          };
        });
    loadAppLocalizations(const Locale('en'));
    final device = App();
    expect(await device.moveTaskToBack(), isTrue);
    expect(await device.tip('hello'), isTrue);
    expect(await device.initShortcuts(), isTrue);
    expect(await device.updateExcludeFromRecents(true), isTrue);
    await device.extractAsset('asset', '/files/asset');
    await device.clearDownloads();
    expect(await device.installPackage('/files/a.apk'), 0);
    expect(await device.openAppSettings(), isFalse);
    expect(await device.hasRootAccess(), isTrue);
    expect(await device.removeCaCertificateWithRoot([1, 2, 3]), isTrue);
    expect(await device.openCertificateSettings(), isTrue);
    expect(await device.getChinaPackageNames(), ['com.a', 'com.b']);
    expect(await device.requestLocalNetworkPermission(), isTrue);
    final packages = await device.getPackages();
    expect(packages.single.packageName, 'com.a');
    expect(
      methods,
      containsAll([
        'moveTaskToBack',
        'tip',
        'initShortcuts',
        'updateExcludeFromRecents',
        'extractAsset',
        'clearDownloads',
        'installPackage',
        'hasRootAccess',
        'removeCaCertificateWithRoot',
        'openCertificateSettings',
        'getChinaPackageNames',
        'requestLocalNetworkPermission',
        'getPackages',
      ]),
    );
  });

  test('locates a CA certificate across the Android stores', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'user': true, 'system': false, 'root': true},
        );

    expect(await App().locateCaCertificate([1, 2, 3]), (
      user: true,
      system: false,
      root: true,
    ));
  });

  test('maps every root CA install outcome', () async {
    String? outcome = 'installed';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => outcome);

    expect(
      await App().installCaCertificateWithRoot([1, 2, 3]),
      MitmInstallOutcome.installed,
    );
    outcome = 'untilReboot';
    expect(
      await App().installCaCertificateWithRoot([1, 2, 3]),
      MitmInstallOutcome.untilReboot,
    );
    outcome = 'denied';
    expect(await App().installCaCertificateWithRoot([1, 2, 3]), isNull);
  });

  test('maps every CA install outcome', () async {
    String? outcome = 'prompted';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => outcome);

    expect(
      await App().installCaCertificate(
        [1, 2, 3],
        name: 'FlClash',
        fileName: 'flclash-ca.crt',
      ),
      MitmInstallOutcome.prompted,
    );
    outcome = 'saved';
    expect(
      await App().installCaCertificate(
        [1, 2, 3],
        name: 'FlClash',
        fileName: 'flclash-ca.crt',
      ),
      MitmInstallOutcome.saved,
    );
    outcome = 'denied';
    expect(
      await App().installCaCertificate(
        [1, 2, 3],
        name: 'FlClash',
        fileName: 'flclash-ca.crt',
      ),
      isNull,
    );
  });

  test('runs the exit hook Android asks for', () async {
    var exits = 0;
    final device = App();
    device.onExit = () async => exits++;
    addTearDown(() => device.onExit = null);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('exit')),
          (_) {},
        );

    expect(exits, 1);
  });

  test('forwards floating keyboard and network changes', () async {
    final device = App();
    expect(device.floatingKeyboard.value, isFalse);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('floatingImeChanged', true),
          ),
          (_) {},
        );
    expect(device.floatingKeyboard.value, isTrue);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('networkChanged', {'wifi': true, 'vpn': false}),
          ),
          (_) {},
        );
  });

  test('an unknown platform method is reported as unimplemented', () async {
    final reply = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('nope')),
          (_) {},
        );

    expect(reply, isNull);
  });

  test('returns the cached own icon without asking Android again', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final packageName = call.arguments['packageName'] as String;
          return packageName == 'com.own'
              ? '/icons/com.own.webp'
              : '/icons/default_icon.webp';
        });

    final device = App();
    final own = await device.getOwnPackageIcon('com.own');
    expect(await device.getOwnPackageIcon('com.own'), same(own));
  });

  test('requests every package icon from Android only once', () async {
    var iconCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          iconCallCount++;
          return '/icons/${call.arguments['packageName']}.png';
        });

    final app = App();
    final results = await Future.wait([
      app.getPackageIcon('com.a'),
      app.getPackageIcon('com.a'),
    ]);
    final cached = await app.getPackageIcon('com.a');

    expect(iconCallCount, 1);
    expect(results.first, isNotNull);
    expect(cached, same(results.first));
    expect(app.getCachedPackageIcon('com.a'), same(results.first));

    await app.getPackageIcon('com.b');

    expect(iconCallCount, 2);
  });

  test(
    'falls back to the default activity icon for unknown packages',
    () async {
      final requested = <String?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final packageName = call.arguments['packageName'] as String?;
            requested.add(packageName);
            return packageName == '' ? '/icons/default_icon.webp' : null;
          });

      final app = App();

      final fallback = await app.getPackageIcon('com.a');
      final defaultIcon = await app.getPackageIcon('');

      expect(fallback, isNotNull);
      expect(fallback, same(defaultIcon));
      expect(requested, ['com.a', '']);

      expect(await app.getPackageIcon('com.b'), same(defaultIcon));
      expect(requested, ['com.a', '', 'com.b']);
    },
  );

  test('a package Android answers with the default icon has none of its '
      'own', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final packageName = call.arguments['packageName'] as String;
          return packageName == 'com.own'
              ? '/icons/com.own.webp'
              : '/icons/default_icon.webp';
        });

    final app = App();
    expect(app.getCachedOwnPackageIcon('com.own'), isNull);
    final own = await app.getOwnPackageIcon('com.own');
    expect(own, isNotNull);
    expect(own, isNot(await app.getPackageIcon('')));
    expect(app.getCachedOwnPackageIcon('com.own')?.icon, same(own));

    expect(app.getCachedOwnPackageIcon('com.gone'), isNull);
    expect(await app.getOwnPackageIcon('com.gone'), isNull);
    expect(app.getCachedOwnPackageIcon('com.gone'), isNotNull);
    expect(app.getCachedOwnPackageIcon('com.gone')?.icon, isNull);
    expect(await app.getOwnPackageIcon(''), isNull);
  });

  test(
    'asks Android for a bounded number of package icons at a time',
    () async {
      var inFlight = 0;
      var peak = 0;
      final release = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            inFlight++;
            peak = max(peak, inFlight);
            await release.future;
            inFlight--;
            return '/icons/${call.arguments['packageName']}.png';
          });

      final app = App();
      final icons = Future.wait([
        for (var i = 0; i < maxConcurrentIconLoads * 2; i++)
          app.getPackageIcon('com.$i'),
      ]);
      await pumpEventQueue();

      expect(inFlight, maxConcurrentIconLoads);

      release.complete();

      expect(await icons, everyElement(isNotNull));
      expect(peak, maxConcurrentIconLoads);
    },
  );

  test('caches a failed package icon lookup', () async {
    var iconCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          iconCallCount++;
          throw PlatformException(code: 'unavailable');
        });

    final app = App();

    expect(await app.getPackageIcon('com.a'), isNull);
    expect(await app.getPackageIcon('com.a'), isNull);
    expect(await app.getPackageIcon(''), isNull);
    expect(iconCallCount, 2);
  });

  test('reads the last process exit info from Android', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return <String, Object?>{
            'reason': 10,
            'timestamp': 1234,
            'description': 'user requested',
          };
        });

    final info = await App().getLastExitInfo();

    expect(receivedCall?.method, 'getLastExitInfo');
    expect(info?.reason, AppExitReason.userRequested);
    expect(info?.timestamp, 1234);
    expect(info?.description, 'user requested');
  });

  test('uses no exit info when Android cannot report one', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await App().getLastExitInfo(), isNull);
  });

  test('uses no exit info when the platform call fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });

    expect(await App().getLastExitInfo(), isNull);
  });

  test('forwards package change notices from Android', () async {
    var changes = 0;
    final app = App();
    app.onPackagesChanged = () => changes++;
    addTearDown(() => app.onPackagesChanged = null);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('packagesChanged')),
          (_) {},
        );

    expect(changes, 1);
  });

  test('reports the installed apps permission Android answers with', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return false;
        });

    expect(await App().isInstalledAppsPermissionGranted(), isFalse);
    expect(await App().requestInstalledAppsPermission(), isFalse);
    expect(methods, [
      'isInstalledAppsPermissionGranted',
      'requestInstalledAppsPermission',
    ]);
  });

  test(
    'treats a missing installed apps permission answer as granted',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      expect(await App().isInstalledAppsPermissionGranted(), isTrue);
      expect(await App().requestInstalledAppsPermission(), isFalse);
    },
  );

  group('downloadFile', () {
    final uri = Uri.https('github.com', '/a.apk');
    late List<MethodCall> calls;

    Map<String, Object?> state(int status, int received, {int reason = 0}) {
      return {
        'status': status,
        'reason': reason,
        'received': received,
        'total': 100,
      };
    }

    void answerQueries(List<Map<String, Object?>?> states) {
      calls = [];
      final pending = [...states];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'enqueueDownload' => 7,
              'queryDownload' =>
                pending.length > 1 ? pending.removeAt(0) : pending.first,
              _ => true,
            };
          });
    }

    Future<void> download({
      CancelToken? cancelToken,
      void Function(int, int)? onReceiveProgress,
    }) {
      return App().downloadFile(
        uri,
        '/files/a.apk',
        title: 'a.apk',
        onReceiveProgress: onReceiveProgress ?? (_, _) {},
        cancelToken: cancelToken ?? CancelToken(),
      );
    }

    Iterable<String> methods() => calls.map((call) => call.method);

    test('follows the system download until it completes', () async {
      answerQueries([state(2, 50), state(8, 100)]);
      final progress = <int>[];

      await download(
        onReceiveProgress: (received, _) => progress.add(received),
      );

      expect(progress, [50, 100]);
      expect(calls.first.arguments, containsPair('path', '/files/a.apk'));
    });

    test('reports why a download failed', () async {
      answerQueries([state(16, 10, reason: 1006)]);

      await expectLater(
        download(),
        throwsA(
          isA<SystemDownloadException>().having(
            (e) => e.reason,
            'reason',
            1006,
          ),
        ),
      );
    });

    test('reports a download removed outside the app', () async {
      answerQueries([null]);

      await expectLater(download(), throwsA(isA<SystemDownloadException>()));
    });

    test('stops following the download once cancelled', () async {
      answerQueries([state(2, 10)]);
      final cancelToken = CancelToken();

      final downloading = download(
        cancelToken: cancelToken,
        onReceiveProgress: (_, _) => cancelToken.cancel(),
      );

      await expectLater(
        downloading,
        throwsA(
          isA<DioException>().having(CancelToken.isCancel, 'isCancel', isTrue),
        ),
      );
      expect(
        methods().where((method) => method == 'queryDownload'),
        hasLength(1),
      );
    });

    test('fails when the download manager is unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'PLATFORM_ERROR');
          });

      await expectLater(
        download(),
        throwsA(
          isA<SystemDownloadException>().having(
            (e) => e.reason,
            'reason',
            isNull,
          ),
        ),
      );
    });
  });
}
