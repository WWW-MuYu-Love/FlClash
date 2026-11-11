// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../on_demand.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DirectSsidRestoreMode)
final directSsidRestoreModeProvider = DirectSsidRestoreModeProvider._();

final class DirectSsidRestoreModeProvider
    extends $NotifierProvider<DirectSsidRestoreMode, Mode?> {
  DirectSsidRestoreModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'directSsidRestoreModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$directSsidRestoreModeHash();

  @$internal
  @override
  DirectSsidRestoreMode create() => DirectSsidRestoreMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Mode? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Mode?>(value),
    );
  }
}

String _$directSsidRestoreModeHash() =>
    r'3b966265f6b3ced8f9d573a6c8cf78a9b619edce';

abstract class _$DirectSsidRestoreMode extends $Notifier<Mode?> {
  Mode? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Mode?, Mode?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Mode?, Mode?>,
              Mode?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(LocationPermissions)
final locationPermissionsProvider = LocationPermissionsProvider._();

final class LocationPermissionsProvider
    extends $NotifierProvider<LocationPermissions, WifiSsidPermission> {
  LocationPermissionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'locationPermissionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$locationPermissionsHash();

  @$internal
  @override
  LocationPermissions create() => LocationPermissions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WifiSsidPermission value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WifiSsidPermission>(value),
    );
  }
}

String _$locationPermissionsHash() =>
    r'e212d0614a941e6f64ee59b1f7e5a0d01764f292';

abstract class _$LocationPermissions extends $Notifier<WifiSsidPermission> {
  WifiSsidPermission build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<WifiSsidPermission, WifiSsidPermission>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WifiSsidPermission, WifiSsidPermission>,
              WifiSsidPermission,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(BatteryOptimizationIgnored)
final batteryOptimizationIgnoredProvider =
    BatteryOptimizationIgnoredProvider._();

final class BatteryOptimizationIgnoredProvider
    extends $StreamNotifierProvider<BatteryOptimizationIgnored, bool> {
  BatteryOptimizationIgnoredProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batteryOptimizationIgnoredProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batteryOptimizationIgnoredHash();

  @$internal
  @override
  BatteryOptimizationIgnored create() => BatteryOptimizationIgnored();
}

String _$batteryOptimizationIgnoredHash() =>
    r'57dec1c4aa0a54c5af1a6934a3d4f78407df8013';

abstract class _$BatteryOptimizationIgnored extends $StreamNotifier<bool> {
  Stream<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
