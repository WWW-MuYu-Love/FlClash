import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

/// A disk-cached outbound-IP answer: the address plus when it was looked up.
typedef _CachedOutboundIp = ({IpInfo ip, DateTime checkedAt});

/// Keyed by the outbound a lookup pins: a node name, `DIRECT`, or
/// [routedOutbound] for whatever the rules pick right now.
@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  /// The disk cache, loaded once per app session. The in-memory copy is
  /// authoritative while the app lives; the disk is just persistence, so a
  /// cold start after iOS kills the app still finds the last answer.
  Map<String, _CachedOutboundIp>? _cacheMap;
  Future<Map<String, _CachedOutboundIp>>? _cacheFuture;

  /// Targets a manual refresh evicted before the cache finished loading;
  /// the load drops them so they are not resurrected.
  final _evicted = <String>{};

  @override
  RoutedProbeState<String, IpInfo> build() {
    unawaited(_cache());
    return buildProbe();
  }

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = _proxyNameOf(target, route);
    // The in-memory cache is already loaded for every probe after the
    // first, so this stays synchronous and costs the lookup no extra turn.
    final cached = _cacheMap != null
        ? _freshCachedIp(proxyName)
        : await _freshCachedIpAsync(proxyName);
    if (cached != null) {
      return {
        target: ProbeAnswer(
          value: cached,
          coreEpoch: route.coreEpoch,
          routeVersion: route.routeVersion,
          hits: const [],
        ),
      };
    }
    final result = await lookupOutboundIp(
      ref.read(coreHandlerProvider),
      proxyName,
    );
    final value = parseOutboundIp(result);
    final exit = result.chains.firstOrNull;
    if (value != null) {
      await _rememberIp(proxyName, value);
    }
    return {
      target: ProbeAnswer(
        value: value,
        coreEpoch: result.coreEpoch,
        routeVersion: result.routeVersion,
        hits: result.hits,
      ),
      // A node leaves through the same address whatever it is asked for.
      if (value != null && exit != null && exit != target)
        exit: ProbeAnswer(
          value: value,
          coreEpoch: result.coreEpoch,
          routeVersion: result.routeVersion,
          hits: result.nodeHits,
        ),
    };
  }

  /// A manual refresh is the user asking for a live answer, so it drops
  /// the disk entries for the refreshed targets before the probe runs.
  /// It stays synchronous so the probe is scheduled on the same turn.
  @override
  void refresh(Iterable<String> targets) {
    final route = ref.read(routeTrackerProvider);
    final proxyNames = targets.map((target) => _proxyNameOf(target, route));
    final cache = _cacheMap;
    if (cache != null) {
      var changed = false;
      for (final name in proxyNames) {
        if (cache.remove(name) != null) {
          changed = true;
        }
      }
      if (changed) {
        unawaited(_persistCache(cache));
      }
    } else {
      _evicted.addAll(proxyNames);
      unawaited(_evictFromDisk(proxyNames));
    }
    super.refresh(targets);
  }

  String _proxyNameOf(String target, RouteState route) =>
      target == routedOutbound && !route.proxied ? directOutbound : target;

  IpInfo? _freshCachedIp(String proxyName) {
    final entry = _cacheMap?[proxyName];
    if (entry == null) {
      return null;
    }
    if (DateTime.now().difference(entry.checkedAt) >= outboundIpCacheMaxAge) {
      return null;
    }
    return entry.ip;
  }

  Future<IpInfo?> _freshCachedIpAsync(String proxyName) async {
    await _cache();
    return _freshCachedIp(proxyName);
  }

  Future<void> _rememberIp(String proxyName, IpInfo ip) async {
    final cache = await _cache();
    cache[proxyName] = (ip: ip, checkedAt: DateTime.now());
    await _persistCache(cache);
  }

  Future<Map<String, _CachedOutboundIp>> _cache() async {
    final cache = _cacheFuture ??= _loadCache();
    return _cacheMap ??= await cache;
  }

  Future<Map<String, _CachedOutboundIp>> _loadCache() async {
    final raw = await preferences.getOutboundIpCache();
    final cache = <String, _CachedOutboundIp>{};
    for (final MapEntry(key: proxyName, value: entry) in raw.entries) {
      if (_evicted.contains(proxyName)) {
        continue;
      }
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final ip = entry['ip'];
      final countryCode = entry['countryCode'];
      final checkedAt = entry['checkedAt'];
      if (ip is! String || countryCode is! String || checkedAt is! int) {
        continue;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(checkedAt);
      if (DateTime.now().difference(at) >= outboundIpCacheMaxAge) {
        continue;
      }
      cache[proxyName] = (
        ip: IpInfo(ip: ip, countryCode: countryCode),
        checkedAt: at,
      );
    }
    return cache;
  }

  Future<void> _evictFromDisk(Iterable<String> proxyNames) async {
    final raw = await preferences.getOutboundIpCache();
    var changed = false;
    for (final name in proxyNames) {
      if (raw.remove(name) != null) {
        changed = true;
      }
    }
    if (changed) {
      await preferences.saveOutboundIpCache(raw);
    }
  }

  Future<void> _persistCache(Map<String, _CachedOutboundIp> cache) {
    final now = DateTime.now();
    final raw = <String, Object?>{};
    for (final MapEntry(key: proxyName, value: entry) in cache.entries) {
      if (now.difference(entry.checkedAt) >= outboundIpCacheMaxAge) {
        continue;
      }
      raw[proxyName] = {
        'ip': entry.ip.ip,
        'countryCode': entry.ip.countryCode,
        'checkedAt': entry.checkedAt.millisecondsSinceEpoch,
      };
    }
    return preferences.saveOutboundIpCache(raw);
  }
}
