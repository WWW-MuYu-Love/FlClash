import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/external_controller.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/core.g.dart';

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
