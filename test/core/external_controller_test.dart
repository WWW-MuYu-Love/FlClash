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

TrackerInfo _sampleConnection(
  String id, {
  int upload = 0,
  int download = 0,
  List<String> chains = const ['Proxy'],
}) {
  return TrackerInfo(
    id: id,
    upload: upload,
    download: download,
    start: DateTime.utc(2026, 11, 10, 10, 0, 0),
    metadata: const Metadata(network: 'tcp', host: 'example.test'),
    chains: chains,
    rule: 'MATCH',
    rulePayload: '',
  );
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

    test('sampleProxyOnly excludes DIRECT traffic from totals and rate', () {
      final sampler = ExternalTrafficSampler();
      final start = DateTime.utc(2026, 11, 10, 10, 0, 0);
      final first = ExternalControllerSnapshot(
        uploadTotal: 10000,
        downloadTotal: 20000,
        connections: [
          _sampleConnection(
            '1',
            upload: 100,
            download: 200,
            chains: const ['DIRECT'],
          ),
          _sampleConnection('2', upload: 300, download: 400),
        ],
      );

      final (firstInstant, firstTotal) = sampler.sampleProxyOnly(first, start);
      expect(firstInstant, isNull);
      expect(firstTotal, const Traffic(up: 300, down: 400));

      final second = ExternalControllerSnapshot(
        uploadTotal: 20000,
        downloadTotal: 40000,
        connections: [
          _sampleConnection(
            '1',
            upload: 1000,
            download: 2000,
            chains: const ['DIRECT'],
          ),
          _sampleConnection('2', upload: 500, download: 600),
        ],
      );
      final (instant, total) = sampler.sampleProxyOnly(
        second,
        start.add(const Duration(seconds: 1)),
      );
      expect(instant, const Traffic(up: 200, down: 200));
      expect(total, const Traffic(up: 500, down: 600));
    });

    test('sampleProxyOnly keeps totals monotonic when a connection closes', () {
      final sampler = ExternalTrafficSampler();
      final start = DateTime.utc(2026, 11, 10, 10, 0, 0);
      final (firstInstant, firstTotal) = sampler.sampleProxyOnly(
        ExternalControllerSnapshot(
          uploadTotal: 1000,
          downloadTotal: 2000,
          connections: [_sampleConnection('2', upload: 300, download: 400)],
        ),
        start,
      );
      expect(firstInstant, isNull);
      expect(firstTotal, const Traffic(up: 300, down: 400));

      final (instant, total) = sampler.sampleProxyOnly(
        const ExternalControllerSnapshot(
          uploadTotal: 2000,
          downloadTotal: 4000,
          connections: [],
        ),
        start.add(const Duration(seconds: 1)),
      );
      expect(instant, const Traffic(up: 0, down: 0));
      expect(total, const Traffic(up: 300, down: 400));
    });

    test('sampleProxyOnly ignores a reused id with smaller counters', () {
      final sampler = ExternalTrafficSampler();
      final start = DateTime.utc(2026, 11, 10, 10, 0, 0);
      sampler.sampleProxyOnly(
        ExternalControllerSnapshot(
          uploadTotal: 1000,
          downloadTotal: 2000,
          connections: [_sampleConnection('2', upload: 300, download: 400)],
        ),
        start,
      );
      final (instant, total) = sampler.sampleProxyOnly(
        ExternalControllerSnapshot(
          uploadTotal: 1100,
          downloadTotal: 2200,
          connections: [_sampleConnection('2', upload: 50, download: 60)],
        ),
        start.add(const Duration(seconds: 1)),
      );
      expect(instant, const Traffic(up: 0, down: 0));
      expect(total, const Traffic(up: 300, down: 400));
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

  group('ExternalControllerClient.fetchMemory', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        // The real /memory endpoint streams one object per second and
        // its first sample is always zero.
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"inuse":0,"oslimit":0}\n');
        await request.response.flush();
        request.response.write('{"inuse":123456,"oslimit":0}\n');
        await request.response.flush();
        // Keep the stream open: fetchMemory must return after the
        // second line instead of waiting for the stream to end.
        await Future<void>.delayed(const Duration(seconds: 5));
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

    test(
      'reads the first non-zero inuse without waiting for the stream',
      () async {
        final memory = await client.fetchMemory().timeout(
          const Duration(seconds: 2),
        );

        expect(memory, 123456);
      },
    );

    test('returns null when the controller answers 401', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.fetchMemory(), isNull);
    });

    test('returns null when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.fetchMemory(), isNull);
    });
  });

  group('ExternalControllerClient.fetchDelay', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'delay': 123}));
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

    test('reads the delay from /proxies/{name}/delay', () async {
      var seenPath = '';
      var seenQuery = <String, String>{};
      await server.close(force: true);
      server = await _serve((request) async {
        seenPath = request.uri.path;
        seenQuery = request.uri.queryParameters;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'delay': 42}));
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final delay = await client.fetchDelay(
        proxyName: 'HK-01',
        testUrl: 'http://www.gstatic.com/generate_204',
        timeout: 8000,
      );

      expect(delay, 42);
      expect(seenPath, '/proxies/HK-01/delay');
      expect(seenQuery['url'], 'http://www.gstatic.com/generate_204');
      expect(seenQuery['timeout'], '8000');
    });

    test('URL-encodes a proxy name with special characters', () async {
      var seenPath = '';
      await server.close(force: true);
      server = await _serve((request) async {
        seenPath = request.uri.path;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'delay': 7}));
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final delay = await client.fetchDelay(
        proxyName: '日本 自动',
        testUrl: 'http://example.test',
        timeout: 5000,
      );

      expect(delay, 7);
      expect(
        seenPath,
        '/proxies/%E6%97%A5%E6%9C%AC%20%E8%87%AA%E5%8A%A8/delay',
      );
    });

    test('sends the secret as a bearer token when set', () async {
      var seenAuth = '';
      await server.close(force: true);
      server = await _serve((request) async {
        seenAuth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'delay': 9}));
        await request.response.close();
      });
      final authed = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        secret: 's3cret',
      );
      addTearDown(authed.close);

      final delay = await authed.fetchDelay(
        proxyName: 'HK-01',
        testUrl: 'http://example.test',
        timeout: 8000,
      );

      expect(delay, 9);
      expect(seenAuth, 'Bearer s3cret');
    });

    test('returns null when the controller answers 404', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(
        await client.fetchDelay(
          proxyName: 'HK-01',
          testUrl: 'http://example.test',
          timeout: 8000,
        ),
        isNull,
      );
    });

    test('returns null when the test itself fails', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(
        await client.fetchDelay(
          proxyName: 'HK-01',
          testUrl: 'http://example.test',
          timeout: 8000,
        ),
        isNull,
      );
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

      expect(
        await client.fetchDelay(
          proxyName: 'HK-01',
          testUrl: 'http://example.test',
          timeout: 8000,
        ),
        isNull,
      );
    });

    test('returns null when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(
        await dead.fetchDelay(
          proxyName: 'HK-01',
          testUrl: 'http://example.test',
          timeout: 8000,
        ),
        isNull,
      );
    });
  });

  group('ExternalControllerClient.selectProxy', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.noContent;
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

    test('PUTs the selected proxy to /proxies/{group}', () async {
      var seenMethod = '';
      var seenPath = '';
      var seenBody = '';
      var seenAuth = '';
      await server.close(force: true);
      server = await _serve((request) async {
        seenMethod = request.method;
        seenPath = request.uri.path;
        seenAuth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        seenBody = await utf8.decodeStream(request);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      final authed = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        secret: 's3cret',
      );
      addTearDown(authed.close);

      expect(await authed.selectProxy('一键代理', '日本自动'), isTrue);
      expect(seenMethod, 'PUT');
      expect(seenPath, '/proxies/%E4%B8%80%E9%94%AE%E4%BB%A3%E7%90%86');
      expect(jsonDecode(seenBody), {'name': '日本自动'});
      expect(seenAuth, 'Bearer s3cret');
    });

    test('returns true on 200 as well as 204', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.selectProxy('group', 'proxy'), isTrue);
    });

    test('returns false on a non-success status', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.selectProxy('group', 'proxy'), isFalse);
    });

    test('returns false without throwing when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.selectProxy('group', 'proxy'), isFalse);
    });
  });

  group('ExternalControllerClient.patchConfigs', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.noContent;
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

    test(
      'PATCHes the given fields to /configs with the bearer secret',
      () async {
        var seenMethod = '';
        var seenPath = '';
        var seenBody = '';
        var seenAuth = '';
        await server.close(force: true);
        server = await _serve((request) async {
          seenMethod = request.method;
          seenPath = request.uri.path;
          seenAuth =
              request.headers.value(HttpHeaders.authorizationHeader) ?? '';
          seenBody = await utf8.decodeStream(request);
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        });
        final authed = ExternalControllerClient(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          secret: 's3cret',
        );
        addTearDown(authed.close);

        expect(await authed.patchConfigs({'mode': 'direct'}), isTrue);
        expect(seenMethod, 'PATCH');
        expect(seenPath, '/configs');
        expect(jsonDecode(seenBody), {'mode': 'direct'});
        expect(seenAuth, 'Bearer s3cret');
      },
    );

    test('returns true on 200 as well as 204', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.patchConfigs({'mode': 'rule'}), isTrue);
    });

    test('returns false on a non-success status', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.patchConfigs({'mode': 'rule'}), isFalse);
    });

    test('returns false without throwing when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.patchConfigs({'mode': 'rule'}), isFalse);
    });
  });

  group('ExternalControllerClient.closeConnections', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.noContent;
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

    test('DELETEs /connections with the bearer secret', () async {
      var seenMethod = '';
      var seenPath = '';
      var seenAuth = '';
      await server.close(force: true);
      server = await _serve((request) async {
        seenMethod = request.method;
        seenPath = request.uri.path;
        seenAuth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      final authed = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        secret: 'secret',
      );
      addTearDown(authed.close);

      expect(await authed.closeConnections(), isTrue);
      expect(seenMethod, 'DELETE');
      expect(seenPath, '/connections');
      expect(seenAuth, 'Bearer secret');
    });

    test('DELETEs one connection at /connections/{id}', () async {
      var seenMethod = '';
      var seenPath = '';
      await server.close(force: true);
      server = await _serve((request) async {
        seenMethod = request.method;
        seenPath = request.uri.path;
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.closeConnection('42'), isTrue);
      expect(seenMethod, 'DELETE');
      expect(seenPath, '/connections/42');
    });

    test('returns true on 200 as well as 204', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.closeConnections(), isTrue);
      expect(await client.closeConnection('42'), isTrue);
    });

    test('returns false on a non-success status', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      expect(await client.closeConnections(), isFalse);
      expect(await client.closeConnection('42'), isFalse);
    });

    test('returns false without throwing when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.closeConnections(), isFalse);
      expect(await dead.closeConnection('42'), isFalse);
    });
  });
  group('ExternalControllerClient probe', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.headers.contentType = ContentType.json;
        final path = request.uri.path;
        if (path == '/probe/services') {
          request.response.write(
            '[{"name":"google","status":"ok","delay":66,"checked-at":1794513170800,"core-epoch":0,"route-version":0}]',
          );
        } else if (path == '/route/check') {
          request.response.write(
            '{"core-epoch":3,"route-version":7,"held":[true,false]}',
          );
        } else if (path == '/probe/outbound-ip') {
          request.response.write(
            '{"url":"https://api.ip.sb/ip","body":"203.0.113.7","delay":120,"chains":["DIRECT"],"core-epoch":3,"route-version":7,"hits":[]}',
          );
        } else if (path == '/mitm/hosts') {
          request.response.write('{"hosts":["example.com"]}');
        } else if (path == '/mitm/exchanges') {
          request.response.write(
            '{"capturing":true,"closed":false,"exchanges":[{"id":7,"start":"2026-11-14T04:50:00.000Z","pending":false,"method":"GET","url":"https://example.com/"}]}',
          );
        } else if (path == '/mitm/exchange') {
          request.response.write(
            '{"id":7,"start":"2026-11-14T04:50:00.000Z","pending":false,"method":"GET","url":"https://example.com/"}',
          );
        } else if (path == '/mitm/body') {
          request.response.write(
            '{"data":"hello","truncated":false,"encoding":""}',
          );
        } else if (path == '/cache/dns/flush') {
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
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

    test('reads the sweep', () async {
      final items = await client.fetchServiceCheck(
        const ServiceCheckParams(timeout: 10000),
      );
      expect(items, hasLength(1));
      expect(items?.first.name, 'google');
      expect(items?.first.status, 'ok');
    });

    test('reads the route check', () async {
      final check = await client.fetchRouteCheck(
        const CheckRoutesParams(routes: []),
      );
      expect(check?.coreEpoch, 3);
      expect(check?.routeVersion, 7);
      expect(check?.held, [true, false]);
    });

    test('reads the outbound IP lookup', () async {
      final result = await client.fetchOutboundIp(
        const OutboundIpParams(
          proxyName: '',
          urls: ['https://api.ip.sb/ip'],
          timeout: 6000,
        ),
      );
      expect(result?.body, '203.0.113.7');
      expect(result?.chains, ['DIRECT']);
      expect(result?.coreEpoch, 3);
    });

    test('clears the DNS cache', () async {
      expect(await client.clearDnsCache(), isTrue);
    });

    test('reads the MITM captures', () async {
      final hosts = await client.fetchMitmDecryptedHosts();
      expect(hosts?.hosts, ['example.com']);
      final list = await client.fetchMitmExchangesByHost('example.com');
      expect(list?.capturing, true);
      expect(list?.exchanges, hasLength(1));
      expect(list?.exchanges.first.id, 7);
      final exchange = await client.fetchMitmExchange(7);
      expect(exchange?.method, 'GET');
      expect(exchange?.url, 'https://example.com/');
      final body = await client.fetchMitmBody(7, response: false);
      expect(body?.data, 'hello');
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

      expect(
        await client.fetchServiceCheck(
          const ServiceCheckParams(timeout: 10000),
        ),
        isNull,
      );
    });
  });

  group('ExternalControllerClient connection-refused backoff', () {
    late HttpServer server;
    late ExternalControllerClient client;
    var now = DateTime.utc(2026, 11, 14);

    setUp(() async {
      now = DateTime.utc(2026, 11, 14);
      server = await _serve((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshotJson));
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clock: () => now,
      );
    });

    tearDown(() async {
      client.close();
      await server.close(force: true);
    });

    Future<int> deadPort() async {
      final port = server.port;
      await server.close(force: true);
      return port;
    }

    Future<HttpServer> servePort(
      int port,
      FutureOr<void> Function(HttpRequest request) handle,
    ) async {
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      bound.listen((request) async {
        try {
          await handle(request);
        } catch (_) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      });
      return bound;
    }

    test('backs off 1s, then 2s, then 4s after refused attempts', () async {
      final port = await deadPort();
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        clock: () => now,
      );
      addTearDown(client.close);

      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isTrue);
      now = now.add(const Duration(milliseconds: 900));
      expect(client.refusedBackoffActive, isTrue);
      now = now.add(const Duration(milliseconds: 200));
      expect(client.refusedBackoffActive, isFalse);

      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isTrue);
      now = now.add(const Duration(seconds: 2, milliseconds: 100));
      expect(client.refusedBackoffActive, isFalse);

      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isTrue);
      now = now.add(const Duration(seconds: 4, milliseconds: 100));
      expect(client.refusedBackoffActive, isFalse);
    });

    test('skips reads inside the window and resumes after it', () async {
      var hits = 0;
      final port = server.port;
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        clock: () => now,
      );
      await server.close(force: true);

      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isTrue);

      server = await servePort(port, (request) async {
        hits++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshotJson));
        await request.response.close();
      });

      expect(await client.fetchConnections(), isNull);
      expect(hits, 0);
      now = now.add(const Duration(seconds: 2));
      expect(await client.fetchConnections(), isNotNull);
      expect(hits, 1);
    });

    test('a successful read clears the backoff streak', () async {
      final port = server.port;
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        clock: () => now,
      );
      await server.close(force: true);

      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isTrue);

      server = await servePort(port, (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshotJson));
        await request.response.close();
      });
      now = now.add(const Duration(seconds: 2));
      expect(await client.fetchConnections(), isNotNull);
      expect(client.refusedBackoffActive, isFalse);

      await server.close(force: true);
      // The pooled connection is dead, so the first read after the close
      // fails on the stale connection instead of refusing; the next read
      // opens a fresh connection and refuses.
      expect(await client.fetchConnections(), isNull);
      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isTrue);
      now = now.add(const Duration(seconds: 1, milliseconds: 100));
      expect(client.refusedBackoffActive, isFalse);
    });

    test('a non-refused failure does not back off', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clock: () => now,
      );

      expect(await client.fetchConnections(), isNull);
      expect(client.refusedBackoffActive, isFalse);
    });
  });
}
