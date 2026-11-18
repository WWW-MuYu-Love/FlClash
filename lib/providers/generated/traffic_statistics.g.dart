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
    r'0e33f57e709a27383f31b155b7d02b9de7c191d7';

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
    required (TrafficStatisticsRange, int) super.argument,
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
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<TrafficStatisticsData> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TrafficStatisticsData> create(Ref ref) {
    final argument = this.argument as (TrafficStatisticsRange, int);
    return trafficStatistics(ref, argument.$1, argument.$2);
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

String _$trafficStatisticsHash() => r'e4287bf846dfbe800eae8d8c02f3676cd0540575';

final class TrafficStatisticsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<TrafficStatisticsData>,
          (TrafficStatisticsRange, int)
        > {
  TrafficStatisticsFamily._()
    : super(
        retry: null,
        name: r'trafficStatisticsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TrafficStatisticsProvider call(TrafficStatisticsRange range, int offset) =>
      TrafficStatisticsProvider._(argument: (range, offset), from: this);

  @override
  String toString() => r'trafficStatisticsProvider';
}
