import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/enum/enum.dart';
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

  group('ExternalControllerClient.setMode', () {
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

    test('PATCHes the routing mode to /configs', () async {
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

      expect(await authed.setMode(Mode.global), isTrue);
      expect(seenMethod, 'PATCH');
      expect(seenPath, '/configs');
      expect(jsonDecode(seenBody), {'mode': 'global'});
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

      expect(await client.setMode(Mode.direct), isTrue);
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

      expect(await client.setMode(Mode.rule), isFalse);
    });

    test('returns false without throwing when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.setMode(Mode.rule), isFalse);
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

  group('ExternalControllerClient mitm', () {
    late HttpServer server;
    late ExternalControllerClient client;

    setUp(() async {
      server = await _serve((request) async {
        request.response.headers.contentType = ContentType.json;
        final path = request.uri.path;
        if (path == '/mitm/hosts') {
          request.response.write('{"hosts":["movies.muyu.love"]}');
        } else if (path == '/mitm/exchanges') {
          request.response.write(
            '{"capturing":true,"exchanges":[{"id":7,"start":"2026-11-12T04:00:00.000Z","method":"GET","url":"https://movies.muyu.love/play","status":200}]}',
          );
        } else if (path == '/mitm/exchange') {
          request.response.write(
            '{"id":7,"start":"2026-11-12T04:00:00.000Z","method":"GET","url":"https://movies.muyu.love/play","status":200,"connection":"1"}',
          );
        } else if (path == '/mitm/body') {
          request.response.write('{"data":"aGVsbG8=","truncated":false}');
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

    test('reads decrypted hosts and exchanges for a host', () async {
      final hosts = await client.fetchMitmDecryptedHosts();
      expect(hosts?.hosts, ['movies.muyu.love']);

      final list = await client.fetchMitmExchangesByHost('movies.muyu.love');
      expect(list?.capturing, isTrue);
      expect(list?.exchanges, hasLength(1));
      expect(list?.exchanges.first.url, 'https://movies.muyu.love/play');

      final exchange = await client.fetchMitmExchange(7);
      expect(exchange?.id, 7);
      expect(exchange?.connection, '1');

      final body = await client.fetchMitmBody(7, response: true);
      expect(body?.data, 'aGVsbG8=');
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

      expect(await client.fetchMitmDecryptedHosts(), isNull);
      expect(await client.fetchMitmExchangesByHost('a.test'), isNull);
      expect(await client.fetchMitmExchange(7), isNull);
      expect(await client.fetchMitmBody(7, response: true), isNull);
    });

    test('returns null when nothing listens', () async {
      final port = server.port;
      await server.close(force: true);
      final dead = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
      );
      addTearDown(dead.close);

      expect(await dead.fetchMitmDecryptedHosts(), isNull);
      expect(await dead.fetchMitmExchangesByHost('a.test'), isNull);
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
            '{"core-epoch":0,"route-version":0,"held":[true]}',
          );
        } else if (path.startsWith('/proxies/') && path.endsWith('/delay')) {
          request.response.write('{"delay":66}');
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

    test('reads the delay, the sweep and the route check', () async {
      final delay = await client.fetchDelay(
        'proxy',
        'https://www.gstatic.com/generate_204',
        const Duration(seconds: 5),
      );
      expect(delay?.value, 66);

      final items = await client.fetchServiceCheck(
        const ServiceCheckParams(timeout: 10000),
      );
      expect(items, hasLength(1));
      expect(items?.first.name, 'google');
      expect(items?.first.status, 'ok');

      final checked = await client.fetchRouteCheck(const CheckRoutesParams());
      expect(checked?.held, [true]);

      expect(await client.clearDnsCache(), isTrue);
    });

    test('maps a gateway timeout to a timed-out delay', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.gatewayTimeout;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final delay = await client.fetchDelay(
        'proxy',
        'https://www.gstatic.com/generate_204',
        const Duration(seconds: 5),
      );
      expect(delay?.value, -1);
    });

    test('maps a failed test to a failed delay', () async {
      await server.close(force: true);
      server = await _serve((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      client = ExternalControllerClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final delay = await client.fetchDelay(
        'proxy',
        'https://www.gstatic.com/generate_204',
        const Duration(seconds: 5),
      );
      expect(delay?.value, -2);
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
        await client.fetchDelay(
          'proxy',
          'https://example.test',
          const Duration(seconds: 5),
        ),
        isNull,
      );
      expect(
        await client.fetchServiceCheck(
          const ServiceCheckParams(timeout: 10000),
        ),
        isNull,
      );
      expect(await client.fetchRouteCheck(const CheckRoutesParams()), isNull);
      expect(await client.clearDnsCache(), isFalse);
    });
  });
}
