import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/battery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/battery');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('is a singleton with a listenable optimization stream', () {
    expect(BatteryOptimization.instance, same(BatteryOptimization.instance));
    expect(BatteryOptimization.instance.onChanged, isNotNull);
  });

  test('asks Android to ignore battery optimizations', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });

    await BatteryOptimization.instance.requestIgnore();

    expect(receivedCall?.method, 'requestIgnoreOptimizations');
  });

  test('has no battery optimization plugin off Android', () {
    expect(batteryOptimization, isNull);
  });
}
