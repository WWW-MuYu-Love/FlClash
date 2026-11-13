import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/xpc_backoff.dart';
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
  final _outboundIpBackoff = XpcEmptyBackoff();

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
    OutboundIpResult result;
    if (_outboundIpBackoff.isBackedOff) {
      result = await lookupOutboundIp(
        ref.read(coreHandlerProvider),
        proxyName,
        route: CoreRoute.app,
      );
    } else {
      try {
        result = await lookupOutboundIp(
          ref.read(coreHandlerProvider),
          proxyName,
        );
        _outboundIpBackoff.noteSuccess();
      } on CoreMethodException catch (error) {
        if (error.code != 'empty_response') {
          rethrow;
        }
        _outboundIpBackoff.noteEmptyResponse();
        result = await lookupOutboundIp(
          ref.read(coreHandlerProvider),
          proxyName,
          route: CoreRoute.app,
        );
      }
    }
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
