import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
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

  // Per-connection last-seen byte counts behind the proxy-only totals.
  final Map<String, ({int upload, int download})> _proxySeen = {};
  int _proxyUploadTotal = 0;
  int _proxyDownloadTotal = 0;
  Traffic? _previousProxyTotal;
  DateTime? _previousProxyAt;

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

  // Proxy-only speed and cumulative totals, matching the App core's
  // onlyStatisticsProxy. The snapshot carries no proxy-only total, so it
  // is built from per-connection deltas: a connection counts unless its
  // chain is exactly DIRECT. A connection that closed between polls loses
  // its tail, and a reused id with smaller counters contributes nothing.
  (Traffic? instant, Traffic total) sampleProxyOnly(
    ExternalControllerSnapshot snapshot,
    DateTime now,
  ) {
    final currentIds = <String>{};
    for (final connection in snapshot.connections) {
      if (connection.chains.firstOrNull == 'DIRECT') {
        continue;
      }
      currentIds.add(connection.id);
      final previous = _proxySeen[connection.id];
      final upDelta = connection.upload - (previous?.upload ?? 0);
      final downDelta = connection.download - (previous?.download ?? 0);
      if (upDelta > 0) {
        _proxyUploadTotal += upDelta;
      }
      if (downDelta > 0) {
        _proxyDownloadTotal += downDelta;
      }
      _proxySeen[connection.id] = (
        upload: connection.upload,
        download: connection.download,
      );
    }
    _proxySeen.removeWhere((id, _) => !currentIds.contains(id));
    final total = Traffic(up: _proxyUploadTotal, down: _proxyDownloadTotal);
    final previousTotal = _previousProxyTotal;
    final previousAt = _previousProxyAt;
    _previousProxyTotal = total;
    _previousProxyAt = now;
    if (previousTotal == null || previousAt == null) {
      return (null, total);
    }
    final elapsed = now.difference(previousAt).inMicroseconds / 1e6;
    if (elapsed <= 0) {
      return (null, total);
    }
    final upDelta = total.up - previousTotal.up;
    final downDelta = total.down - previousTotal.down;
    if (upDelta < 0 || downDelta < 0) {
      return (null, total);
    }
    return (Traffic(up: upDelta / elapsed, down: downDelta / elapsed), total);
  }
}

class ExternalControllerClient {
  ExternalControllerClient({required this.baseUri, this.secret = ''})
    : _http = HttpClient();

  final Uri baseUri;
  final String secret;
  final HttpClient _http;

  static const _fetchTimeout = Duration(seconds: 2);

  // /memory ticks once a second and its first sample is zero, so reading
  // a real value takes two ticks.
  static const _memoryReadTimeout = Duration(seconds: 4);

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

  // GET /memory returns the core behind 9090's resident memory. The
  // endpoint streams one JSON object per second, and its first sample
  // is always zero, so this reads until the first non-zero `inuse`
  // and then closes the connection instead of waiting for the stream
  // to end.
  Future<int?> fetchMemory() async {
    try {
      final request = await _http
          .getUrl(baseUri.replace(path: '/memory'))
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      var read = 0;
      await for (final line
          in response
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(_memoryReadTimeout)) {
        read++;
        final json = jsonDecode(line);
        if (json is Map<String, Object?>) {
          final inuse = json['inuse'];
          if (inuse is num && inuse > 0) {
            return inuse.toInt();
          }
        }
        if (read >= 3) {
          break;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // GET /mitm/hosts returns the hosts with recorded decrypted exchanges.
  Future<MitmDecryptedHosts?> fetchMitmDecryptedHosts() async {
    try {
      final request = await _http
          .getUrl(baseUri.replace(path: '/mitm/hosts'))
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
      final json = jsonDecode(body);
      return json is Map<String, Object?>
          ? MitmDecryptedHosts.fromJson(json)
          : null;
    } catch (_) {
      return null;
    }
  }

  // GET /mitm/exchanges returns the recorded exchanges for one host.
  Future<MitmExchangeList?> fetchMitmExchangesByHost(String host) async {
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              path: '/mitm/exchanges',
              queryParameters: {'host': host},
            ),
          )
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
      final json = jsonDecode(body);
      return json is Map<String, Object?>
          ? MitmExchangeList.fromJson(json)
          : null;
    } catch (_) {
      return null;
    }
  }

  // GET /mitm/exchange returns one recorded exchange, or null.
  Future<MitmExchange?> fetchMitmExchange(int id) async {
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              path: '/mitm/exchange',
              queryParameters: {'id': '$id'},
            ),
          )
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
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? MitmExchange.fromJson(json) : null;
    } catch (_) {
      return null;
    }
  }

  // GET /mitm/body returns one side of a recorded exchange, or null.
  Future<MitmBody?> fetchMitmBody(int id, {required bool response}) async {
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              path: '/mitm/body',
              queryParameters: {'id': '$id', 'response': '$response'},
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final httpResponse = await request.close().timeout(_fetchTimeout);
      if (httpResponse.statusCode != HttpStatus.ok) {
        await httpResponse.drain<void>();
        return null;
      }
      final body = await httpResponse
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? MitmBody.fromJson(json) : null;
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

  // PATCH /configs changes the routing mode on the core behind 9090.
  // The extension core answers 204 on success, so a false return means
  // the request itself failed (the tunnel is down or 9090 is unreachable).
  Future<bool> setMode(Mode mode) async {
    try {
      final request = await _http
          .patchUrl(
            baseUri.replace(pathSegments: [...baseUri.pathSegments, 'configs']),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'mode': mode.name}));
      final response = await request.close().timeout(_fetchTimeout);
      await response.drain<void>();
      return response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  // DELETE /connections closes every connection on the core behind 9090;
  // DELETE /connections/{id} closes one. The extension core answers 204
  // even for an unknown id, so a false return means the request itself
  // failed (the tunnel is down or 9090 is unreachable).
  Future<bool> closeConnections() => _delete(['connections']);

  Future<bool> closeConnection(String id) => _delete(['connections', id]);

  Future<bool> _delete(List<String> pathSegments) async {
    try {
      final request = await _http
          .deleteUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, ...pathSegments],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
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
