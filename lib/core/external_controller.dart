import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';

class ExternalControllerSnapshot {
  const ExternalControllerSnapshot({
    required this.uploadTotal,
    required this.downloadTotal,
    required this.connections,
  });

  final int uploadTotal;
  final int downloadTotal;
  final List<TrackerInfo> connections;

  static ExternalControllerSnapshot? fromJson(Object? data) {
    if (data is! Map) {
      return null;
    }
    final uploadTotal = data['uploadTotal'];
    final downloadTotal = data['downloadTotal'];
    if (uploadTotal is! num || downloadTotal is! num) {
      return null;
    }
    return ExternalControllerSnapshot(
      uploadTotal: uploadTotal.toInt(),
      downloadTotal: downloadTotal.toInt(),
      connections: trackerInfosOf(data),
    );
  }
}

class ExternalTrafficSampler {
  ExternalControllerSnapshot? _previous;
  DateTime? _previousAt;

  Traffic? sample(ExternalControllerSnapshot snapshot, DateTime now) {
    final previous = _previous;
    final previousAt = _previousAt;
    _previous = snapshot;
    _previousAt = now;
    if (previous == null || previousAt == null) {
      return null;
    }
    final elapsed = now.difference(previousAt).inMicroseconds / 1e6;
    if (elapsed <= 0) {
      return null;
    }
    final upDelta = snapshot.uploadTotal - previous.uploadTotal;
    final downDelta = snapshot.downloadTotal - previous.downloadTotal;
    if (upDelta < 0 || downDelta < 0) {
      return null;
    }
    return Traffic(up: upDelta / elapsed, down: downDelta / elapsed);
  }
}

class ExternalControllerClient {
  ExternalControllerClient({required this.baseUri, this.secret = ''})
    : _http = HttpClient();

  final Uri baseUri;
  final String secret;
  final HttpClient _http;

  static const _fetchTimeout = Duration(seconds: 2);

  Future<ExternalControllerSnapshot?> fetchConnections() async {
    try {
      final request = await _http
          .getUrl(baseUri.replace(path: '/connections'))
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      return ExternalControllerSnapshot.fromJson(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  Future<bool> selectProxy(String groupName, String proxyName) async {
    try {
      final request = await _http
          .putUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'proxies', groupName],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'name': proxyName}));
      final response = await request.close().timeout(_fetchTimeout);
      await response.drain<void>();
      return response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  void close() {
    _http.close(force: true);
  }
}
