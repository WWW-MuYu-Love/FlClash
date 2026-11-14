import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

/// Keyed by the outbound a lookup pins: a node name, `DIRECT`, or
/// [routedOutbound] for whatever the rules pick right now.
@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  @override
  RoutedProbeState<String, IpInfo> build() => buildProbe();

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    // 9090 first: the routing core answers the lookup. The app core only
    // matters when the tunnel is down, so it is the fallback, not a retry.
    OutboundIpResult? via9090;
    try {
      via9090 = await ref
          .read(externalControllerClientProvider)
          .fetchOutboundIp(
            OutboundIpParams(
              proxyName: proxyName,
              urls: ipInfoSources.keys.toList(),
              timeout: outboundIpTimeoutDuration.inMilliseconds,
            ),
          );
    } catch (_) {
      // Fall through to the App core fallback below.
    }
    final result =
        via9090 ??
        await lookupOutboundIp(
          ref.read(coreHandlerProvider),
          proxyName,
          route: CoreRoute.app,
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
