import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _resolveSource(String relativePath) {
  final direct = File(relativePath);
  if (direct.existsSync()) {
    return direct;
  }
  final inPlugin = File('plugins/wifi_ssid/$relativePath');
  if (inPlugin.existsSync()) {
    return inPlugin;
  }
  return direct;
}

void main() {
  late String pluginSource;
  late String packageManifest;

  setUpAll(() {
    pluginSource = _resolveSource(
      'ios/wifi_ssid/Sources/wifi_ssid/WifiSsidPlugin.swift',
    ).readAsStringSync();
    packageManifest = _resolveSource(
      'ios/wifi_ssid/Package.swift',
    ).readAsStringSync();
  });

  test('iOS reads the SSID off the platform thread', () {
    final fetchIndex = pluginSource.indexOf('NEHotspotNetwork.fetchCurrent {');
    expect(fetchIndex, isNonNegative);
    final mainQueueIndex = pluginSource.indexOf(
      'DispatchQueue.main.async {',
      fetchIndex,
    );
    expect(mainQueueIndex, isNonNegative);
    final resultIndex = pluginSource.indexOf(
      'result(network?.ssid)',
      mainQueueIndex,
    );
    expect(resultIndex, isNonNegative);
    expect(
      pluginSource.substring(fetchIndex, mainQueueIndex),
      isNot(contains('result(')),
      reason: 'fetchCurrent answers off the calling thread',
    );
  });

  test('iOS does not use the deprecated SSID API', () {
    expect(
      pluginSource,
      isNot(contains('CNCopyCurrentNetworkInfo')),
      reason: 'deprecated in iOS 26 and always returns nil there',
    );
  });

  test('iOS reports the permission as granted', () {
    expect(
      pluginSource,
      contains('result(WifiSsidPermission.granted.rawValue)'),
      reason:
          'the installed VPN configuration satisfies Apple\'s condition for fetchCurrent',
    );
    expect(
      pluginSource,
      isNot(contains('CLLocationManager')),
      reason: 'no location permission is requested on this path',
    );
  });

  test('iOS links the NetworkExtension framework', () {
    expect(packageManifest, contains('.linkedFramework("NetworkExtension")'));
    expect(packageManifest, contains('.iOS(.v15)'));
  });

  test('iOS calls the registrar messenger method', () {
    expect(
      pluginSource,
      contains('registrar.messenger()'),
      reason:
          'the iOS registrar exposes messenger as a method, unlike macOS',
    );
  });
}
