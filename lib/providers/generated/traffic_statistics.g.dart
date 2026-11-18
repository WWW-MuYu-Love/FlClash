// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../traffic_statistics.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Records closed connections while the tunnel is up: opens and traffic
/// updates arrive as core events, and the live snapshot says which ones
/// have closed. A connection the event queue dropped still shows up in the
/// snapshot and is picked up from there.

@ProviderFor(TrafficStatisticsRecorder)
final trafficStatisticsRecorderProvider = TrafficStatisticsRecorderProvider._();

/// Records closed connections while the tunnel is up: opens and traffic
/// updates arrive as core events, and the live snapshot says which ones
/// have closed. A connection the event queue dropped still shows up in the
/// snapshot and is picked up from there.
final class TrafficStatisticsRecorderProvider
    extends $NotifierProvider<TrafficStatisticsRecorder, void> {
  /// Records closed connections while the tunnel is up: opens and traffic
  /// updates arrive as core events, and the live snapshot says which ones
  /// have closed. A connection the event queue dropped still shows up in the
  /// snapshot and is picked up from there.
  TrafficStatisticsRecorderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trafficStatisticsRecorderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trafficStatisticsRecorderHash();

  @$internal
  @override
  TrafficStatisticsRecorder create() => TrafficStatisticsRecorder();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$trafficStatisticsRecorderHash() =>
    r'781964af10df3c7a1f5ba01d2ae661baf47e91dc';

/// Records closed connections while the tunnel is up: opens and traffic
/// updates arrive as core events, and the live snapshot says which ones
/// have closed. A connection the event queue dropped still shows up in the
/// snapshot and is picked up from there.

abstract class _$TrafficStatisticsRecorder extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(trafficStatistics)
final trafficStatisticsProvider = TrafficStatisticsFamily._();

final class TrafficStatisticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TrafficStatisticsData>,
          TrafficStatisticsData,
          FutureOr<TrafficStatisticsData>
        >
    with
        $FutureModifier<TrafficStatisticsData>,
        $FutureProvider<TrafficStatisticsData> {
  TrafficStatisticsProvider._({
    required TrafficStatisticsFamily super.from,
    required TrafficStatisticsRange super.argument,
  }) : super(
         retry: null,
         name: r'trafficStatisticsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$trafficStatisticsHash();

  @override
  String toString() {
    return r'trafficStatisticsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<TrafficStatisticsData> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TrafficStatisticsData> create(Ref ref) {
    final argument = this.argument as TrafficStatisticsRange;
    return trafficStatistics(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TrafficStatisticsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$trafficStatisticsHash() => r'1d097ac1d336343182d3e08bb1a43e94a2f72fac';

final class TrafficStatisticsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<TrafficStatisticsData>,
          TrafficStatisticsRange
        > {
  TrafficStatisticsFamily._()
    : super(
        retry: null,
        name: r'trafficStatisticsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TrafficStatisticsProvider call(TrafficStatisticsRange range) =>
      TrafficStatisticsProvider._(argument: range, from: this);

  @override
  String toString() => r'trafficStatisticsProvider';
}
