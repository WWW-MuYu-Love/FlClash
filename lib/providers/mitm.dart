import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/mitm_body.dart';
import 'package:fl_clash/common/mitm_capture_disk.dart';
import 'package:fl_clash/common/mitm_module.dart';
import 'package:fl_clash/common/mitm_trust.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rust_api/rust_api.dart' show transcodeCharset;

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'database.dart';
import 'state.dart';

part 'generated/mitm.g.dart';

const _exchangesRefreshInterval = Duration(seconds: 2);

/// Lowercases a connection host and strips a port, matching the core's
/// decrypted-hosts normalization.
String normalizeMitmHost(String host) {
  final trimmed = host.trim().toLowerCase();
  final port = trimmed.lastIndexOf(':');
  if (port < 0) {
    return trimmed;
  }
  return trimmed.substring(0, port);
}

/// Hosts with recorded decrypted exchanges. On iOS the persisted
/// captures on the shared disk are the source, so hosts stay listed
/// after the tunnel stops. Live in-flight hosts need the 9090
/// controller, which is not wired up yet.
@riverpod
Future<Set<String>> mitmDecryptedHosts(Ref ref) async {
  if (system.isIOS) {
    return mitmCaptureHosts(
      await readMitmCaptureExchanges(await appPath.mitmCapturesDirPath),
    );
  }
  // No core, no decrypted hosts: never call into the core while it is down.
  if (ref.read(coreStatusProvider) != CoreStatus.connected) {
    return const {};
  }
  final hosts = await ref.read(coreHandlerProvider).getMitmDecryptedHosts();
  return {for (final host in hosts.hosts) normalizeMitmHost(host)};
}

@Riverpod(keepAlive: true)
class MitmCa extends _$MitmCa {
  @override
  Future<MitmCertificate?> build() {
    return ref.read(coreHandlerProvider).getMitmCertificate();
  }

  Future<void> generate() async {
    final certificate = await ref
        .read(coreHandlerProvider)
        .generateMitmCertificate();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(certificate);
  }
}

@Riverpod(keepAlive: true)
MitmTrustStore? mitmTrustStore(Ref ref) => mitmTrustStoreForPlatform();

/// Whether this device trusts the CA. A check records the CA it found
/// trusted, which is the one the Core decrypts HTTPS with.
@Riverpod(keepAlive: true)
class MitmTrustState extends _$MitmTrustState {
  @override
  Future<MitmTrustCheck> build() async {
    return _check(await ref.watch(mitmCaProvider.future));
  }

  Future<MitmTrustCheck> _check(MitmCertificate? ca) async {
    final store = ref.read(mitmTrustStoreProvider);
    final MitmTrustCheck check;
    if (ca == null) {
      check = const MitmTrustCheck(MitmTrust.notGenerated);
    } else if (store == null) {
      check = const MitmTrustCheck(MitmTrust.notInstalled);
    } else {
      final core = ref.read(coreHandlerProvider);
      check = await store.check(
        ca,
        () => core.issueMitmCertificate(mitmCheckHost),
      );
    }
    if (ref.mounted) {
      _record(ca, check);
    }
    return check;
  }

  void _record(MitmCertificate? ca, MitmTrustCheck check) {
    final trusted = check.trust == MitmTrust.ready ? ca?.fingerprint : null;
    if (ref.read(patchClashConfigProvider).mitm.trustedFingerprint == trusted) {
      return;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            mitm: state.mitm.copyWith(trustedFingerprint: trusted),
          ),
        );
  }

  Future<void>? _refreshing;

  /// Calls while a check runs share it, since each check runs the platform's
  /// trust tools.
  Future<void> refresh() {
    if (state.isLoading) {
      return future.then((_) {}, onError: (_) {});
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final next = await AsyncValue.guard(
      () async => _check(await ref.read(mitmCaProvider.future)),
    );
    if (ref.mounted) {
      state = next;
    }
  }

  Future<MitmInstallOutcome?> install() async {
    final ca = await ref.read(mitmCaProvider.future);
    final store = ref.read(mitmTrustStoreProvider);
    if (ca == null || store == null || ref.read(safeModeProvider)) {
      return null;
    }
    final MitmInstallOutcome outcome;
    try {
      outcome = await store.install(ca);
    } finally {
      if (store is AndroidMitmTrustStore && ref.mounted) {
        ref.invalidate(rootAccessProvider);
      }
    }
    if (outcome == MitmInstallOutcome.installed ||
        outcome == MitmInstallOutcome.untilReboot) {
      await refresh();
    }
    return outcome;
  }

  /// False when the old CA is left in the trust store for the user to remove,
  /// as safe mode always leaves it.
  Future<bool> regenerate() async {
    final old = await ref.read(mitmCaProvider.future);
    final store = ref.read(mitmTrustStoreProvider);
    final trust = state.value?.trust;
    var removed = true;
    if (old != null &&
        store != null &&
        (trust == MitmTrust.ready || trust == MitmTrust.untrusted)) {
      try {
        removed = !ref.read(safeModeProvider) && await store.remove(old);
      } catch (error) {
        commonPrint.log(
          'Removing the old MITM certificate failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
        removed = false;
      }
      if (store is AndroidMitmTrustStore && ref.mounted) {
        ref.invalidate(rootAccessProvider);
      }
    }
    await ref.read(mitmCaProvider.notifier).generate();
    return removed;
  }
}

/// Completed exchanges from the persisted captures on the shared disk.
/// In-flight exchanges are not visible here yet: they need the 9090
/// controller, which is not wired up yet.
Future<MitmExchangeList> _mitmExchangesIOS(
  Ref ref,
  String host, {
  required bool running,
  required bool capture,
}) async {
  final disk = await readMitmCaptureExchanges(
    await appPath.mitmCapturesDirPath,
  );
  final byId = <int, MitmExchangeSummary>{
    for (final exchange in disk)
      if (normalizeMitmHost(Uri.tryParse(exchange.url)?.host ?? '') == host)
        exchange.id: mitmCaptureSummary(exchange),
  };
  final exchanges = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  return MitmExchangeList(
    capturing: capture,
    since: exchanges.isEmpty ? null : exchanges.first.start,
    exchanges: exchanges,
    closed: false,
  );
}

/// Fetched again while shown, until the connection has closed and none of its
/// requests is pending. Keyed by host: the capture store never sees the
/// tracker's ids. On iOS the store is the persisted captures on the
/// shared disk; in-flight exchanges are not visible yet.
@riverpod
Future<MitmExchangeList> mitmExchanges(Ref ref, String host) async {
  final running = ref.watch(isStartProvider);
  final capture = ref.watch(
    patchClashConfigProvider.select(
      (state) => state.mitm.enable && state.mitm.capture,
    ),
  );
  final list = system.isIOS
      ? await _mitmExchangesIOS(ref, host, running: running, capture: capture)
      : await ref.read(coreHandlerProvider).getMitmExchangesByHost(host);
  final settled =
      list.closed && !list.exchanges.any((exchange) => exchange.pending);
  // With the tunnel stopped the disk copy is static, so skip the refresh.
  if (!settled && ref.mounted && (running || !system.isIOS)) {
    final timer = Timer(_exchangesRefreshInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return list;
}

@riverpod
Future<MitmExchange?> mitmExchange(Ref ref, int id) async {
  if (system.isIOS) {
    final disk = await readMitmCaptureExchange(
      await appPath.mitmCapturesDirPath,
      id,
    );
    if (disk != null && !disk.pending) {
      return disk;
    }
  }
  final running = !system.isIOS || ref.read(isStartProvider);
  final exchange = await ref.read(coreHandlerProvider).getMitmExchange(id);
  if (exchange != null && exchange.pending && running && ref.mounted) {
    final timer = Timer(_exchangesRefreshInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return exchange;
}

@riverpod
Future<MitmBodyContent?> mitmBody(
  Ref ref,
  int id, {
  required bool response,
  required String contentType,
}) async {
  final MitmBody? body;
  if (system.isIOS) {
    body =
        await readMitmCaptureBody(
          await appPath.mitmCapturesDirPath,
          id,
          response: response,
        ) ??
        await ref
            .read(coreHandlerProvider)
            .getMitmBody(id, response: response);
  } else {
    body = await ref
        .read(coreHandlerProvider)
        .getMitmBody(id, response: response);
  }
  if (body == null) {
    return null;
  }
  final content = await compute(readMitmBody, (body, contentType));
  if (content.charset.isEmpty) {
    return content;
  }
  final Uint8List? utf8Bytes;
  try {
    utf8Bytes = await mitmCharsetTranscoder(
      bytes: content.bytes,
      label: content.charset,
      lossy: content.truncated,
    );
  } catch (error) {
    commonPrint.log('Reading ${content.charset} failed: $error');
    return content;
  }
  if (utf8Bytes == null) {
    return content;
  }
  return compute(readMitmCharsetText, (content, utf8Bytes, contentType));
}

typedef MitmCharsetTranscoder =
    Future<Uint8List?> Function({
      required List<int> bytes,
      required String label,
      required bool lossy,
    });

@visibleForTesting
MitmCharsetTranscoder mitmCharsetTranscoder = transcodeCharset;

/// Whether the user was told, this run, what a copied or exported request
/// can carry.
@Riverpod(keepAlive: true)
class MitmExportWarned extends _$MitmExportWarned {
  @override
  bool build() => false;

  void accept() => state = true;
}

/// Why the Core skips each of the user's hostnames, by the line.
@riverpod
Future<Map<String, String>> mitmHostnameIssues(Ref ref) async {
  final hostname = ref.watch(
    patchClashConfigProvider.select((state) => state.mitm.hostname),
  );
  final issues = await _issuesOf(ref, MitmRules(hostname: hostname));
  return issues[MitmList.hostname] ?? const {};
}

Future<Map<MitmList, Map<String, String>>> _issuesOf(
  Ref ref,
  MitmRules mitm,
) async {
  final issues = await ref.read(coreHandlerProvider).validateMitm(mitm);
  return {
    for (final MapEntry(key: list, value: lines) in issues.entries)
      list: {
        for (final MapEntry(key: index, value: issue) in lines.entries)
          mitm.linesOf(list)[index]: issue,
      },
  };
}

typedef MitmModuleDetails = ({
  MitmModuleContent content,
  Map<MitmList, Map<String, String>> issues,
});

MitmModuleContent _parseModuleSource(MitmModuleSource source) =>
    parseMitmModule(
      source.content,
      values: source.arguments,
      resources: source.resources,
    );

/// Null while the module's content is not on disk.
@riverpod
Future<MitmModuleDetails?> mitmModuleDetails(Ref ref, int id) async {
  final module = ref.watch(
    mitmModulesProvider.select(
      (state) => state.value?.firstWhereOrNull((item) => item.id == id),
    ),
  );
  if (module == null) {
    return null;
  }
  final file = File(join(await appPath.mitmModulesDirPath, module.fileName));
  if (!await file.exists()) {
    return null;
  }
  final content = await compute(
    _parseModuleSource,
    MitmModuleSource(
      content: await file.readAsString(),
      arguments: module.arguments,
      resources: module.resources,
    ),
  );
  return (content: content, issues: await _issuesOf(ref, content.mitm));
}
