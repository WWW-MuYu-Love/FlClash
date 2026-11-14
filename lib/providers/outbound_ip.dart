import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
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

  Future<OutboundIpResult?> _outboundIpViaXpc(String proxyName) async {
    if (ref.read(runningVpnOptionsProvider)?.enable != true) {
      return null;
    }
    try {
      final result = await lookupOutboundIp(
        ref.read(coreHandlerProvider),
        proxyName,
      ).timeout(outboundIpXpcAttemptDuration);
      return parseOutboundIp(result) == null ? null : result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    final viaXpc = await _outboundIpViaXpc(proxyName);
    OutboundIpResult? via9090;
    if (viaXpc == null) {
      try {
        via9090 =
            externalControllerUp(
              tunnelUp: ref.read(runningVpnOptionsProvider)?.enable == true,
            )
            ? await ref
                  .read(externalControllerClientProvider)
                  .fetchOutboundIp(
                    OutboundIpParams(
                      proxyName: proxyName,
                      urls: ipInfoSources.keys.toList(),
                      timeout: outboundIpTimeoutDuration.inMilliseconds,
                    ),
                  )
            : null;
      } catch (_) {
        // Fall through to the App core fallback below.
      }
    }
    final result =
        viaXpc ??
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
