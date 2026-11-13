import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/mixin.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/xpc_backoff.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/service_status.g.dart';

@Riverpod(keepAlive: true)
class ServiceStatus extends _$ServiceStatus
    with RoutedProbe<ServiceTarget, ServiceCheck> {
  final _serviceCheckBackoff = XpcEmptyBackoff();

  @override
  RoutedProbeState<ServiceTarget, ServiceCheck> build() => buildProbe();

  @override
  bool isFailure(ServiceCheck value) =>
      value.status == ServiceProbeStatus.timeout ||
      value.status == ServiceProbeStatus.failed;

  Future<List<ServiceCheckItem>?> _serviceCheckOver9090(
    RouteState route,
    ServiceTarget target,
  ) async {
    try {
      return await ref
          .read(externalControllerClientProvider)
          .fetchServiceCheck(
            ServiceCheckParams(
              proxyName: route.proxied ? '' : directOutbound,
              names: [target.id],
              timeout: probeTimeoutDuration.inMilliseconds,
            ),
          );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<ServiceTarget, ProbeAnswer<ServiceCheck>>> probe(
    ServiceTarget target,
    RouteState route,
  ) async {
    Map<ServiceTarget, ServiceCheck> checks;
    final items = await _serviceCheckOver9090(route, target);
    if (items != null) {
      checks = serviceChecksOf(items);
    } else if (_serviceCheckBackoff.isBackedOff) {
      checks = await checkServices(
        ref.read(coreHandlerProvider),
        proxyName: route.proxied ? '' : directOutbound,
        targets: [target],
        route: CoreRoute.app,
      );
    } else {
      try {
        checks = await checkServices(
          ref.read(coreHandlerProvider),
          proxyName: route.proxied ? '' : directOutbound,
          targets: [target],
        );
        _serviceCheckBackoff.noteSuccess();
      } on CoreMethodException catch (error) {
        if (error.code != 'empty_response' ||
            ref.read(runningVpnOptionsProvider)?.enable != true) {
          rethrow;
        }
        _serviceCheckBackoff.noteEmptyResponse();
        checks = await checkServices(
          ref.read(coreHandlerProvider),
          proxyName: route.proxied ? '' : directOutbound,
          targets: [target],
          route: CoreRoute.app,
        );
      }
    }
    final check = checks[target];
    return {
      if (check != null)
        target: ProbeAnswer(
          value: check,
          coreEpoch: check.coreEpoch,
          routeVersion: check.routeVersion,
          hits: check.hits,
        ),
    };
  }
}

/// How many of [enabledServiceTargets] the dashboard card has room for, which
/// its sheet marks as shown there.
@Riverpod(keepAlive: true)
class ShownServiceCount extends _$ShownServiceCount
    with AutoDisposeNotifierMixin {
  @override
  int build() => 2;
}

@riverpod
List<ServiceTarget> serviceTargets(Ref ref) {
  final order = ref.watch(
    appSettingProvider.select((state) => SelectValue(state.serviceOrder)),
  );
  return orderServiceTargets(order.value);
}

@riverpod
List<ServiceTarget> enabledServiceTargets(Ref ref) {
  final targets = ref.watch(serviceTargetsProvider);
  final disabled = ref.watch(
    appSettingProvider.select((state) => SelectValue(state.disabledServices)),
  );
  final enabled = [
    for (final target in targets)
      if (!disabled.value.contains(target.id)) target,
  ];
  return enabled.isEmpty ? targets : enabled;
}
