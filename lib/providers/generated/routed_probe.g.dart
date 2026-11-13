// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../routed_probe.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How long a probe waits before retrying 9090 when the first attempt finds
/// it not yet listening. The tunnel may still be starting; the App core is
/// not a substitute while it is up, so the probe gives 9090 a second chance
/// instead of falling back immediately.

@ProviderFor(probe9090RetryDelay)
final probe9090RetryDelayProvider = Probe9090RetryDelayProvider._();

/// How long a probe waits before retrying 9090 when the first attempt finds
/// it not yet listening. The tunnel may still be starting; the App core is
/// not a substitute while it is up, so the probe gives 9090 a second chance
/// instead of falling back immediately.

final class Probe9090RetryDelayProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// How long a probe waits before retrying 9090 when the first attempt finds
  /// it not yet listening. The tunnel may still be starting; the App core is
  /// not a substitute while it is up, so the probe gives 9090 a second chance
  /// instead of falling back immediately.
  Probe9090RetryDelayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'probe9090RetryDelayProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$probe9090RetryDelayHash();

  @$internal
  @override
  $ProviderElement<Duration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration create(Ref ref) {
    return probe9090RetryDelay(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$probe9090RetryDelayHash() =>
    r'a2d911c5f16acf54cb2db7e73ef6562bb32ff953';
