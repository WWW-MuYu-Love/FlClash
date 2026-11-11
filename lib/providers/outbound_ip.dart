import 'dart:async';

import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'config.dart';
import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

/// How often the dashboard IP info re-probes itself while auto-refresh is on.
const outboundIpAutoRefreshInterval = Duration(seconds: 60);

/// Keyed by the outbound a lookup pins: a node name, `DIRECT`, or
/// [routedOutbound] for whatever the rules pick right now.
@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  Timer? _autoRefreshTimer;

  @override
  RoutedProbeState<String, IpInfo> build() {
    final state = buildProbe();
    ref.onDispose(() {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    });
    ref.listen(
      appSettingProvider,
      (_, next) => _updateAutoRefresh(next.autoRefreshOutboundIp),
    );
    _updateAutoRefresh(ref.read(appSettingProvider).autoRefreshOutboundIp);
    return state;
  }

  void _updateAutoRefresh(bool enabled) {
    final running = _autoRefreshTimer != null;
    if (enabled == running) {
      return;
    }
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    if (!enabled) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(outboundIpAutoRefreshInterval, (_) {
      final targets = watchedTargets.toList();
      if (targets.isNotEmpty) {
        refresh(targets);
      }
    });
  }

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    final result = await lookupOutboundIp(
      ref.read(coreHandlerProvider),
      proxyName,
    );
    final value = parseOutboundIp(result);
    final exit = result.chains.firstOrNull;
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
}
