import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _snapshotJson = {
  'downloadTotal': 1000,
  'uploadTotal': 2000,
  'connections': [
    {
      'id': '1',
      'upload': 100,
      'download': 200,
      'start': '2026-11-10T10:00:00.000Z',
      'metadata': {'network': 'tcp', 'host': 'example.test'},
      'chains': ['Proxy'],
      'rule': 'MATCH',
      'rulePayload': '',
    },
  ],
};

Future<HttpServer> _serve(
  FutureOr<void> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handle(request);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  });
  return server;
}

void main() {
  group('ExternalControllerSnapshot.fromJson', () {
    test('parses totals and the connection list', () {
      final snapshot = ExternalControllerSnapshot.fromJson(_snapshotJson);

      expect(snapshot, isNotNull);
      expect(snapshot!.uploadTotal, 2000);
      expect(snapshot.downloadTotal, 1000);
      expect(snapshot.connections, hasLength(1));
      expect(snapshot.connections.first.id, '1');
      expect(snapshot.connections.first.metadata.host, 'example.test');
    });

    test('returns null without numeric totals', () {
      expect(ExternalControllerSnapshot.fromJson({}), isNull);
      expect(ExternalControllerSnapshot.fromJson({'uploadTotal': 'x'}), isNull);
    });

    test('tolerates a missing connection list', () {
      final snapshot = ExternalControllerSnapshot.fromJson({
        'uploadTotal': 1,
        'downloadTotal': 2,
      });

      expect(snapshot, isNotNull);
      expect(snapshot!.connections, isEmpty);
    });
  });

  group('ExternalTrafficSampler', () {
    test('returns null for the first sample, then the per-second rate', () {
      final sampler = ExternalTrafficSampler();
      const first = ExternalControllerSnapshot(
        uploadTotal: 1000,
        downloadTotal: 2000,
        connections: [],
      );
      const second = ExternalControllerSnapshot(
        uploadTotal: 1500,
        downloadTotal: 2800,
        connections: [],
      );
      final start = DateTime.utc(2026, 11, 10, 10, 0, 0);

      expect(sampler.sample(first, start), isNull);
      final traffic = sampler.sample(
        second,
        start.add(const Duration(seconds: 1)),
      );
      expect(traffic, const Traffic(up: 500, down: 800));
    });

    test('returns null and re-baselines when the totals reset', () {
      final sampler = ExternalTrafficSampler();
      final start = DateTime.utc(2026, 11, 10, 10, 0, 0);
      sampler.sample(
        const ExternalControllerSnapshot(
          uploadTotal: 1000,
          downloadTotal: 2000,
          connections: [],
        ),
        start,
      );
      final reset = sampler.sample(
        const ExternalControllerSnapshot(
          uploadTotal: 10,
          downloadTotal: 20,
          connections: [],
        ),
        start.add(const Duration(seconds: 1)),
      );
      expect(reset, isNull);
      final next = sampler.sample(
        const ExternalControllerSnapshot(
          uploadTotal: 110,
          downloadTotal: 220,
          connections: [],
        ),
        start.add(const Duration(seconds: 2)),
      );
      expect(next, const Traffic(up: 100, down: 200));
    });
  });

  group('ExternalControllerClient.fetchConnections', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshotJson));
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );
    });

    tearDown(() async {
      client.close();
      await server.close(force: true);
    });

    test('reads the snapshot from /connections', () async {
      final snapshot = await client.fetchConnections();

      expect(snapshot, isNotNull);
      expect(snapshot!.uploadTotal, 2000);
      expect(snapshot.downloadTotal, 1000);
      expect(snapshot.connections, hasLength(1));
    });

    test('sends the secret as a bearer token when set', () async {
      var seenAuth = '';
      await server.close(force: true);
      server = await _serve((request) async {
        seenAuth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshotJson));
        await request.response.close();
      });
      final authed = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        secret: 's3cret',
      );
      addTearDown(authed.close);

      final snapshot = await authed.fetchConnections();

      expect(snapshot, isNotNull);
      expect(seenAuth, 'Bearer s3cret');
    });

    test('returns null when the controller answers 401', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.fetchConnections(), isNull);
    });

    test('returns null on a malformed body', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.write('not json');
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.fetchConnections(), isNull);
    });

    test('returns null when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.fetchConnections(), isNull);
    });
  });
}
