import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
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
  ExternalControllerClient({
    required this.baseUri,
    this.secret = '',
    DateTime Function()? clock,
  }) : _http = HttpClient(),
       _clock = clock ?? DateTime.now {
    // The controller lives on localhost. Dart's HttpClient otherwise routes
    // through the iOS system proxy when it is on, so a request to 9090 is
    // sent to the mixed port and never reaches the controller.
    _http.findProxy = (_) => 'DIRECT';
  }

  final Uri baseUri;
  final String secret;
  final HttpClient _http;
  final DateTime Function() _clock;

  static const _fetchTimeout = Duration(seconds: 2);

  // The controller's listener comes up asynchronously with the extension
  // core, so the first requests after the tunnel starts hit connection
  // refused. Each refused attempt holds off the next one for 1s, then 2s,
  // then 4s; a single answered request clears the streak.
  static const _refusedBackoffs = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];
  int _refusedStreak = 0;
  DateTime? _refusedUntil;
  DateTime? _reachableSince;

  /// True while a connection-refused backoff is holding off new attempts.
  bool get refusedBackoffActive =>
      _refusedUntil != null && _clock().isBefore(_refusedUntil!);

  DateTime? get controllerReachableSince => _reachableSince;

  bool _skipWhileRefused() => refusedBackoffActive;

  void _noteRefused(Object error) {
    if (!_isConnectionRefused(error)) {
      return;
    }
    _reachableSince = null;
    final backoff =
        _refusedBackoffs[_refusedStreak.clamp(0, _refusedBackoffs.length - 1)];
    _refusedStreak++;
    _refusedUntil = _clock().add(backoff);
  }

  void _noteReachable() {
    _reachableSince ??= _clock();
    _refusedStreak = 0;
    _refusedUntil = null;
  }

  static bool _isConnectionRefused(Object error) {
    final osError = error is SocketException ? error.osError : null;
    // 61 is ECONNREFUSED on iOS/macOS, 111 on Linux, 10061 on Windows.
    return osError != null &&
        (osError.errorCode == 61 ||
            osError.errorCode == 111 ||
            osError.errorCode == 10061);
  }

  /// True when the last controller call failed with 401: the tunnel is up, only the secret is stale.
  bool unauthorized = false;

  void _noteStatus(HttpClientResponse response) {
    unauthorized = response.statusCode == HttpStatus.unauthorized;
    _noteReachable();
  }

  final Set<String> _failing = {};

  void _reportFailure(String key, String detail) {
    if (_failing.add(key)) {
      commonPrint.log('9090 $key failed: $detail', logLevel: LogLevel.warning);
    }
  }

  void _reportSuccess(String key) {
    if (_failing.remove(key)) {
      commonPrint.log('9090 $key recovered');
    }
  }

  static const _listenerReadyPoll = Duration(milliseconds: 100);

  /// Retries [attempt] only while the listener has never answered; once answered, a failure is final.
  Future<T?> fetchSettled<T>(
    Duration timeout,
    Future<T?> Function() attempt,
  ) async {
    final deadline = _clock().add(timeout);
    while (true) {
      final now = _clock();
      if (!now.isBefore(deadline)) {
        return null;
      }
      if (_reachableSince == null && refusedBackoffActive) {
        await _sleepUntil(now.add(_listenerReadyPoll), deadline);
        continue;
      }
      final value = await attempt();
      if (value != null) {
        return value;
      }
      if (refusedBackoffActive && _reachableSince == null) {
        continue;
      }
      return null;
    }
  }

  Future<void> _sleepUntil(DateTime until, DateTime deadline) async {
    final end = until.isBefore(deadline) ? until : deadline;
    final wait = end.difference(_clock());
    if (wait <= Duration.zero) {
      return;
    }
    await Future.delayed(wait);
  }

  // /memory ticks once a second and its first sample is zero, so reading
  // a real value takes two ticks.
  static const _memoryReadTimeout = Duration(seconds: 4);

  Future<ExternalControllerSnapshot?> fetchConnections() async {
    if (_skipWhileRefused()) {
      return null;
    }
    try {
      final request = await _http
          .getUrl(baseUri.replace(path: '/connections'))
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('connections', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final snapshot = ExternalControllerSnapshot.fromJson(jsonDecode(body));
      if (snapshot == null) {
        _reportFailure('connections', 'bad response');
        return null;
      }
      _reportSuccess('connections');
      return snapshot;
    } catch (error) {
      _reportFailure('connections', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // GET /memory returns the core behind 9090's resident memory. The
  // endpoint streams one JSON object per second, and its first sample
  // is always zero, so this reads until the first non-zero `inuse`
  // and then closes the connection instead of waiting for the stream
  // to end.
  Future<int?> fetchMemory() async {
    if (_skipWhileRefused()) {
      return null;
    }
    try {
      final request = await _http
          .getUrl(baseUri.replace(path: '/memory'))
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('memory', 'HTTP ${response.statusCode}');
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
            _reportSuccess('memory');
            return inuse.toInt();
          }
        }
        if (read >= 3) {
          break;
        }
      }
      _reportFailure('memory', 'no non-zero sample');
      return null;
    } catch (error) {
      _reportFailure('memory', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // GET /proxies/{name}/delay?url=<testUrl>&timeout=<ms> measures the
  // delay through the named proxy on the core behind 9090. A null return
  // means the request itself failed (the tunnel is down, the proxy does
  // not exist, or the secret is stale); the core answers 503 when the
  // test itself fails. The `expected` status range is omitted, so any
  // status counts as a success.
  Future<int?> fetchDelay({
    required String proxyName,
    required String testUrl,
    required int timeout,
  }) async {
    if (_skipWhileRefused()) {
      return null;
    }
    final httpTimeout = coreGuardFor(timeout);
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              pathSegments: [
                ...baseUri.pathSegments,
                'proxies',
                proxyName,
                'delay',
              ],
              queryParameters: {'url': testUrl, 'timeout': '$timeout'},
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(httpTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('delay', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) {
        _reportFailure('delay', 'bad response');
        return null;
      }
      final delay = json['delay'];
      if (delay is! num) {
        _reportFailure('delay', 'no delay');
        return null;
      }
      _reportSuccess('delay');
      return delay.toInt();
    } catch (error) {
      _reportFailure('delay', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // PATCH /configs applies the given fields on the core behind 9090.
  Future<bool> patchConfigs(Map<String, Object?> body) async {
    try {
      final request = await _http
          .patchUrl(baseUri.replace(path: '/configs'))
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      await response.drain<void>();
      final ok =
          response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
      if (ok) {
        _reportSuccess('patch-configs');
      } else {
        _reportFailure('patch-configs', 'HTTP ${response.statusCode}');
      }
      return ok;
    } catch (error) {
      _reportFailure('patch-configs', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return false;
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
      _noteStatus(response);
      await response.drain<void>();
      final ok =
          response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
      if (ok) {
        _reportSuccess('select-proxy');
      } else {
        _reportFailure('select-proxy', 'HTTP ${response.statusCode}');
      }
      return ok;
    } catch (error) {
      _reportFailure('select-proxy', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return false;
    }
  }

  // POST /probe/services runs the service sweep on the core behind 9090
  // and answers the checked items. A null return means the request
  // itself failed (the tunnel is down or the secret is stale).
  Future<List<ServiceCheckItem>?> fetchServiceCheck(
    ServiceCheckParams params,
  ) async {
    if (_skipWhileRefused()) {
      return null;
    }
    final httpTimeout = coreGuardFor(
      params.timeout,
      budgetFactor: serviceSweepBudgetFactor,
    );
    try {
      final request = await _http
          .postUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'probe', 'services'],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(params.toJson()));
      final response = await request.close().timeout(httpTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('service-check', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      if (json is! List) {
        _reportFailure('service-check', 'bad response');
        return null;
      }
      _reportSuccess('service-check');
      return [
        for (final item in json)
          if (item is Map<String, Object?>) ServiceCheckItem.fromJson(item),
      ];
    } catch (error) {
      _reportFailure('service-check', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  Future<RouteCheck?> fetchRouteCheck(CheckRoutesParams params) async {
    if (_skipWhileRefused()) {
      return null;
    }
    final httpTimeout = coreGuardFor(probeTimeoutDuration.inMilliseconds);
    try {
      final request = await _http
          .postUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'route', 'check'],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(params.toJson()));
      final response = await request.close().timeout(httpTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('route-check', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) {
        _reportFailure('route-check', 'bad response');
        return null;
      }
      _reportSuccess('route-check');
      return RouteCheck.fromJson(json);
    } catch (error) {
      _reportFailure('route-check', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // POST /probe/outbound-ip returns the outbound IP lookup from the core
  // behind 9090, or null when it cannot be reached or answers nothing.
  Future<OutboundIpResult?> fetchOutboundIp(OutboundIpParams params) async {
    if (_skipWhileRefused()) {
      return null;
    }
    final httpTimeout = coreGuardFor(params.timeout);
    try {
      final request = await _http
          .postUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'probe', 'outbound-ip'],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(params.toJson()));
      final response = await request.close().timeout(httpTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('outbound-ip', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) {
        _reportFailure('outbound-ip', 'bad response');
        return null;
      }
      _reportSuccess('outbound-ip');
      return OutboundIpResult.fromJson(json);
    } catch (error) {
      _reportFailure('outbound-ip', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // POST /cache/dns/flush clears the DNS cache on the core behind 9090.
  // The core answers 204; a false return means the request itself failed
  // (the tunnel is down or 9090 is unreachable).
  Future<bool> clearDnsCache() async {
    try {
      final request = await _http
          .postUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'cache', 'dns', 'flush'],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      await response.drain<void>();
      final ok =
          response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
      if (ok) {
        _reportSuccess('dns-clear');
      } else {
        _reportFailure('dns-clear', 'HTTP ${response.statusCode}');
      }
      return ok;
    } catch (error) {
      _reportFailure('dns-clear', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return false;
    }
  }

  // GET /mitm/hosts returns the hosts with recorded decrypted exchanges.
  Future<MitmDecryptedHosts?> fetchMitmDecryptedHosts() async {
    if (_skipWhileRefused()) {
      return null;
    }
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'mitm', 'hosts'],
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('mitm-hosts', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      final hosts = json is Map<String, Object?>
          ? MitmDecryptedHosts.fromJson(json)
          : null;
      if (hosts == null) {
        _reportFailure('mitm-hosts', 'bad response');
        return null;
      }
      _reportSuccess('mitm-hosts');
      // A successful read with no hosts is the invisible case: the capture
      // info stays hidden with no failure line. Log it once per streak.
      if (hosts.hosts.isEmpty) {
        _reportFailure('mitm-hosts-empty', 'no decrypted hosts');
      } else {
        _reportSuccess('mitm-hosts-empty');
      }
      return hosts;
    } catch (error) {
      _reportFailure('mitm-hosts', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // GET /mitm/exchanges returns the recorded exchanges for one host.
  Future<MitmExchangeList?> fetchMitmExchangesByHost(String host) async {
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'mitm', 'exchanges'],
              queryParameters: {'host': host},
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('mitm-exchanges', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      final exchanges = json is Map<String, Object?>
          ? MitmExchangeList.fromJson(json)
          : null;
      if (exchanges == null) {
        _reportFailure('mitm-exchanges', 'bad response');
        return null;
      }
      _reportSuccess('mitm-exchanges');
      return exchanges;
    } catch (error) {
      _reportFailure('mitm-exchanges', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // GET /mitm/exchange returns one recorded exchange, or null.
  Future<MitmExchange?> fetchMitmExchange(int id) async {
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'mitm', 'exchange'],
              queryParameters: {'id': '$id'},
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final response = await request.close().timeout(_fetchTimeout);
      _noteStatus(response);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        _reportFailure('mitm-exchange', 'HTTP ${response.statusCode}');
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      final exchange = json is Map<String, Object?>
          ? MitmExchange.fromJson(json)
          : null;
      if (exchange == null) {
        _reportFailure('mitm-exchange', 'bad response');
        return null;
      }
      _reportSuccess('mitm-exchange');
      return exchange;
    } catch (error) {
      _reportFailure('mitm-exchange', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
    }
  }

  // GET /mitm/body returns one side of a recorded exchange, or null.
  Future<MitmBody?> fetchMitmBody(int id, {required bool response}) async {
    try {
      final request = await _http
          .getUrl(
            baseUri.replace(
              pathSegments: [...baseUri.pathSegments, 'mitm', 'body'],
              queryParameters: {'id': '$id', 'response': '$response'},
            ),
          )
          .timeout(_fetchTimeout);
      if (secret.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final httpResponse = await request.close().timeout(_fetchTimeout);
      _noteStatus(httpResponse);
      if (httpResponse.statusCode != HttpStatus.ok) {
        await httpResponse.drain<void>();
        _reportFailure('mitm-body', 'HTTP ${httpResponse.statusCode}');
        return null;
      }
      final body = await httpResponse
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      final json = jsonDecode(body);
      final mitmBody = json is Map<String, Object?>
          ? MitmBody.fromJson(json)
          : null;
      if (mitmBody == null) {
        _reportFailure('mitm-body', 'bad response');
        return null;
      }
      _reportSuccess('mitm-body');
      return mitmBody;
    } catch (error) {
      _reportFailure('mitm-body', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return null;
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
      _noteStatus(response);
      await response.drain<void>();
      final ok =
          response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.ok;
      if (ok) {
        _reportSuccess('close-connections');
      } else {
        _reportFailure('close-connections', 'HTTP ${response.statusCode}');
      }
      return ok;
    } catch (error) {
      _reportFailure('close-connections', compactError(error));
      _noteRefused(error);
      unauthorized = false;
      return false;
    }
  }

  void close() {
    _http.close(force: true);
  }
}
