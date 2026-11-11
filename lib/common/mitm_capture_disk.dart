import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart' show join;

/// Captures under `<home>/mitm/captures/`: `<id>.json` meta plus raw
/// `<id>.request` / `<id>.response` bodies, read straight from disk.
Future<List<MitmExchange>> readMitmCaptureExchanges(
  String capturesDirPath,
) async {
  final directory = Directory(capturesDirPath);
  if (!await directory.exists()) {
    return const [];
  }
  final exchanges = <MitmExchange>[];
  await for (final entity in directory.list()) {
    if (entity is! File || !entity.path.endsWith('.json')) {
      continue;
    }
    final exchange = await readMitmCaptureExchangeFile(entity);
    if (exchange != null) {
      exchanges.add(exchange);
    }
  }
  exchanges.sort((a, b) => a.id.compareTo(b.id));
  return exchanges;
}

Future<MitmExchange?> readMitmCaptureExchange(
  String capturesDirPath,
  int id,
) async {
  final file = File(join(capturesDirPath, '$id.json'));
  if (!await file.exists()) {
    return null;
  }
  return readMitmCaptureExchangeFile(file);
}

Future<MitmExchange?> readMitmCaptureExchangeFile(File file) async {
  try {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, Object?>) {
      return null;
    }
    return MitmExchange.fromJson(json);
  } catch (_) {
    return null;
  }
}

/// One side of a persisted capture, or null when it has no file yet.
Future<MitmBody?> readMitmCaptureBody(
  String capturesDirPath,
  int id, {
  required bool response,
}) async {
  final meta = File(join(capturesDirPath, '$id.json'));
  if (!await meta.exists()) {
    return null;
  }
  final suffix = response ? '.response' : '.request';
  final bodyFile = File(join(capturesDirPath, '$id$suffix'));
  if (!await bodyFile.exists()) {
    return null;
  }
  try {
    final json = jsonDecode(await meta.readAsString());
    final truncated = json is Map<String, Object?>
        ? json[response ? 'response-truncated' : 'request-truncated'] == true
        : false;
    final bytes = await bodyFile.readAsBytes();
    return MitmBody(data: base64Encode(bytes), truncated: truncated);
  } catch (_) {
    return null;
  }
}

Set<String> mitmCaptureHosts(List<MitmExchange> exchanges) {
  final hosts = <String>{};
  for (final exchange in exchanges) {
    final host = Uri.tryParse(exchange.url)?.host.toLowerCase() ?? '';
    if (host.isNotEmpty) {
      hosts.add(host);
    }
  }
  return hosts;
}

MitmExchangeSummary mitmCaptureSummary(MitmExchange exchange) {
  return MitmExchangeSummary(
    id: exchange.id,
    start: exchange.start,
    pending: exchange.pending,
    duration: exchange.duration,
    method: exchange.method,
    url: exchange.url,
    status: exchange.status,
    requestSize: exchange.requestSize,
    responseSize: exchange.responseSize,
    error: exchange.error,
  );
}
