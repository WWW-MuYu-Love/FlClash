import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/mitm_capture_disk.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _writeExchange(
  Directory dir,
  int id,
  String url, {
  String request = '',
  String response = '',
}) async {
  final meta = {
    'id': id,
    'start': '2026-11-12T00:00:00.000Z',
    'pending': false,
    'method': 'GET',
    'url': url,
    'status': 200,
    'request-size': request.length,
    'response-size': response.length,
    'request-truncated': false,
    'response-truncated': true,
  };
  await File('${dir.path}/$id.json').writeAsString(jsonEncode(meta));
  if (request.isNotEmpty) {
    await File('${dir.path}/$id.request').writeAsString(request);
  }
  if (response.isNotEmpty) {
    await File('${dir.path}/$id.response').writeAsString(response);
  }
}

void main() {
  test('disk captures list, filter by host and read bodies', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    await _writeExchange(
      dir,
      2,
      'https://cdn.muyu.love/a.js',
      response: 'hello',
    );
    await _writeExchange(
      dir,
      1,
      'https://movies.muyu.love/play',
      request: 'ping',
    );
    await File('${dir.path}/bad.json').writeAsString('not json');

    final exchanges = await readMitmCaptureExchanges(dir.path);
    expect(exchanges.map((e) => e.id).toList(), [1, 2]);
    expect(mitmCaptureHosts(exchanges), {'movies.muyu.love', 'cdn.muyu.love'});

    final exchange = await readMitmCaptureExchange(dir.path, 2);
    expect(exchange?.url, 'https://cdn.muyu.love/a.js');
    expect(await readMitmCaptureExchange(dir.path, 99), isNull);

    final body = await readMitmCaptureBody(dir.path, 2, response: true);
    expect(body?.data, base64Encode(utf8.encode('hello')));
    expect(body?.truncated, isTrue);
    expect(await readMitmCaptureBody(dir.path, 1, response: false), isNotNull);
    expect(await readMitmCaptureBody(dir.path, 1, response: true), isNull);
  });
}
