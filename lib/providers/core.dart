import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/core.g.dart';

/// Whether the 9090 controller is expected to answer. On iOS it lives in
/// the extension core and only listens while the tunnel runs; everywhere
/// else the local core answers it.
bool externalControllerUp({required bool tunnelUp}) =>
    !system.isIOS || tunnelUp;

@Riverpod(keepAlive: true)
CoreController coreHandler(Ref ref) => coreController;

@Riverpod(keepAlive: true)
ExternalControllerClient externalControllerClient(Ref ref) {
  final patch = ref.watch(patchClashConfigProvider);
  final address = patch.externalController.value;
  final client = ExternalControllerClient(
    baseUri: Uri.parse(
      'http://${address.isEmpty ? '127.0.0.1:9090' : address}',
    ),
    secret: patch.secret,
  );
  ref.onDispose(client.close);
  return client;
}
