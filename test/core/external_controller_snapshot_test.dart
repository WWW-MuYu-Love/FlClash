import 'package:fl_clash/core/external_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A connection exactly as mihomo's GET /connections emits it: Go's
/// encoding/json on statistic.TrackerInfo, with time.Time as RFC3339Nano
/// (9 fractional digits) and the `,string` ports as JSON strings.
Map<String, Object?> realisticConnection({
  Object? start = '2026-11-10T20:41:00.123456789+08:00',
  Object? dnsMode = 'fake-ip',
  Object? chains = const ['Proxy', 'DIRECT'],
  Object? rulePayload = 'example.com',
  Map<String, Object?>? metadataOverride,
}) {
  final metadata = <String, Object?>{
    'network': 'tcp',
    'type': 'HTTP',
    'sourceIP': '10.7.0.1',
    'destinationIP': '93.184.216.34',
    'sourceGeoIP': <String>[],
    'destinationGeoIP': <String>['CN'],
    'sourceIPASN': '',
    'destinationIPASN': '',
    'sourcePort': '54321',
    'destinationPort': '443',
    'inboundIP': '10.7.0.1',
    'inboundPort': '7890',
    'inboundName': '',
    'inboundUser': '',
    'rematchName': '',
    'host': 'example.com',
    'dnsMode': dnsMode,
    'uid': 0,
    'process': '',
    'processPath': '',
    'specialProxy': '',
    'specialRules': '',
    'remoteDestination': '',
    'dscp': 0,
    'sniffHost': '',
  };
  if (metadataOverride != null) {
    metadata.addAll(metadataOverride);
  }
  final connection = <String, Object?>{
    'id': '3f2f0a4e-1b1c-4d5e-8f9a-0b1c2d3e4f5a',
    'metadata': metadata,
    'upload': 100,
    'download': 200,
    'start': start,
    'chains': chains,
    'providerChains': const ['Proxy'],
    'rule': 'DomainSuffix',
    'rulePayload': rulePayload,
  };
  return connection;
}

Map<String, Object?> snapshotWith(List<Object?> connections) => {
  'downloadTotal': 1000,
  'uploadTotal': 2000,
  'connections': connections,
  'memory': 123456,
};

void main() {
  group('realistic mihomo /connections payload', () {
    test('parses a full connection with nanosecond start', () {
      final snapshot = ExternalControllerSnapshot.fromJson(
        snapshotWith([realisticConnection()]),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, hasLength(1));
      expect(snapshot.connections.first.id, startsWith('3f2f0a4e'));
      expect(snapshot.connections.first.metadata.host, 'example.com');
      expect(snapshot.connections.first.chains, ['Proxy', 'DIRECT']);
    });

    test('connections null keeps the snapshot and totals', () {
      final snapshot = ExternalControllerSnapshot.fromJson({
        'downloadTotal': 1000,
        'uploadTotal': 2000,
        'connections': null,
        'memory': 123456,
      });

      expect(snapshot, isNotNull);
      expect(snapshot!.uploadTotal, 2000);
      expect(snapshot.downloadTotal, 1000);
      expect(snapshot.connections, isEmpty);
    });

    test('empty connections array keeps the snapshot and totals', () {
      final snapshot = ExternalControllerSnapshot.fromJson(snapshotWith([]));

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, isEmpty);
    });

    test('dnsMode unknown is tolerated as null', () {
      final snapshot = ExternalControllerSnapshot.fromJson(
        snapshotWith([realisticConnection(dnsMode: 'unknown')]),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, hasLength(1));
      expect(snapshot.connections.first.metadata.dnsMode, isNull);
    });

    test('chains null becomes an empty list', () {
      final snapshot = ExternalControllerSnapshot.fromJson(
        snapshotWith([realisticConnection(chains: null)]),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, hasLength(1));
      expect(snapshot.connections.first.chains, isEmpty);
    });

    test('rulePayload missing skips only that connection', () {
      final connection = realisticConnection();
      connection.remove('rulePayload');
      final snapshot = ExternalControllerSnapshot.fromJson(
        snapshotWith([connection]),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.uploadTotal, 2000);
      expect(snapshot.downloadTotal, 1000);
      expect(snapshot.connections, isEmpty);
    });

    test('one malformed connection among good ones', () {
      final bad = realisticConnection();
      bad.remove('id');
      final snapshot = ExternalControllerSnapshot.fromJson(
        snapshotWith([realisticConnection(), bad]),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, hasLength(1));
    });

    test('sourcePort as a number becomes a string', () {
      final snapshot = ExternalControllerSnapshot.fromJson(
        snapshotWith([
          realisticConnection(metadataOverride: {'sourcePort': 54321}),
        ]),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, hasLength(1));
      expect(snapshot.connections.first.metadata.sourcePort, '54321');
    });
  });
}
