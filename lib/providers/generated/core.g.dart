// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../core.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(coreHandler)
final coreHandlerProvider = CoreHandlerProvider._();

final class CoreHandlerProvider
    extends $FunctionalProvider<CoreController, CoreController, CoreController>
    with $Provider<CoreController> {
  CoreHandlerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coreHandlerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coreHandlerHash();

  @$internal
  @override
  $ProviderElement<CoreController> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CoreController create(Ref ref) {
    return coreHandler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CoreController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CoreController>(value),
    );
  }
}

String _$coreHandlerHash() => r'b00cbd733d546e4edd1a0b9b98e9ace46da1eff2';

@ProviderFor(externalControllerClient)
final externalControllerClientProvider = ExternalControllerClientProvider._();

final class ExternalControllerClientProvider
    extends
        $FunctionalProvider<
          ExternalControllerClient,
          ExternalControllerClient,
          ExternalControllerClient
        >
    with $Provider<ExternalControllerClient> {
  ExternalControllerClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'externalControllerClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$externalControllerClientHash();

  @$internal
  @override
  $ProviderElement<ExternalControllerClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ExternalControllerClient create(Ref ref) {
    return externalControllerClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExternalControllerClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExternalControllerClient>(value),
    );
  }
}

String _$externalControllerClientHash() =>
    r'5a075d0b54edee6123d9d7891950cd6da0eb4964';
