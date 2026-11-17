// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../effective_mode.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The mode the routing core actually runs; while the tunnel is up it
/// asks the core behind 9090, whose mode an SSID override can change.

@ProviderFor(EffectiveMode)
final effectiveModeProvider = EffectiveModeProvider._();

/// The mode the routing core actually runs; while the tunnel is up it
/// asks the core behind 9090, whose mode an SSID override can change.
final class EffectiveModeProvider
    extends $NotifierProvider<EffectiveMode, Mode> {
  /// The mode the routing core actually runs; while the tunnel is up it
  /// asks the core behind 9090, whose mode an SSID override can change.
  EffectiveModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'effectiveModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$effectiveModeHash();

  @$internal
  @override
  EffectiveMode create() => EffectiveMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Mode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Mode>(value),
    );
  }
}

String _$effectiveModeHash() => r'd4b812a96b6c51b7304b27e8b2420d390f3f2705';

/// The mode the routing core actually runs; while the tunnel is up it
/// asks the core behind 9090, whose mode an SSID override can change.

abstract class _$EffectiveMode extends $Notifier<Mode> {
  Mode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Mode, Mode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Mode, Mode>,
              Mode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
