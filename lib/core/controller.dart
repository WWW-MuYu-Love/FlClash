import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/spill.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';

/// Every [CoreHandlerInterface] method passes through unless redeclared here.
extension type CoreController._(CoreHandlerInterface _interface)
    implements CoreHandlerInterface {
  static CoreController? _instance;

  factory CoreController() {
    return _instance ??= CoreController._(
      system.isMobile ? coreLib! : coreService!,
    );
  }

  @visibleForTesting
  factory CoreController.test(CoreHandlerInterface interface) {
    return _instance = CoreController._(interface);
  }

  @visibleForTesting
  CoreController.scoped(this._interface);

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  static Future<void> ensureHomeDir() async {
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    await system.grantHomeDirAccess(homePath);
  }

  static Future<void> initGeo() async {
    final homePath = await appPath.homeDirPath;
    const geoFileNameList = [MMDB, GEOIP, GEOSITE, ASN];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(join(homePath, geoFileName));
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final asset = 'assets/data/$geoFileName';
        // rootBundle inflates the asset on the platform thread, which Android
        // shares with the UI: the four files stall frames for over 100 ms.
        if (app case final app?) {
          await app.extractAsset(asset, geoFile.path);
          continue;
        }
        final data = await rootBundle.load(asset);
        final List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
      }
    } catch (e) {
      commonPrint.log(
        'Failed to initialize geo data: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  /// The zashboard web dashboard bundled with the app, served by the
  /// external controller at /ui. Built in (not downloaded) so the panel
  /// works without reaching GitHub at first start.
  static const zashboardVersion = '3.30.0';
  static const _zashboardAsset = 'assets/data/zashboard.zip';
  static const _zashboardVersionFile = '.flclash-zashboard-version';

  static Future<void> initZashboard() async {
    final homePath = await appPath.homeDirPath;
    final targetDir = Directory(join(homePath, 'ui', 'zashboard'));
    try {
      final versionFile = File(join(targetDir.path, _zashboardVersionFile));
      if (await versionFile.exists() &&
          (await versionFile.readAsString()).trim() == zashboardVersion) {
        return;
      }
      final data = await rootBundle.load(_zashboardAsset);
      final List<int> bytes = data.buffer.asUint8List();
      await extractZashboardArchive(
        zipBytes: bytes,
        targetDir: targetDir,
        version: zashboardVersion,
      );
    } catch (e) {
      // The dashboard is optional: a failed extraction only leaves /ui
      // empty, so log it and let the core start without the panel.
      commonPrint.log(
        'Failed to initialize zashboard: $e',
        logLevel: LogLevel.error,
      );
    }
  }

  /// Extracts the bundled zashboard archive into [targetDir], stripping
  /// the single top-level `dist/` directory the release zip carries, and
  /// records [version] so a newer bundled build replaces the copy. Paths
  /// are kept inside [targetDir].
  @visibleForTesting
  static Future<void> extractZashboardArchive({
    required List<int> zipBytes,
    required Directory targetDir,
    required String version,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final outPath = _zashboardEntryPath(targetDir.path, file.name);
      if (outPath == null) {
        continue;
      }
      await Directory(dirname(outPath)).create(recursive: true);
      await File(outPath).writeAsBytes(file.content as List<int>, flush: true);
    }
    await File(
      join(targetDir.path, _zashboardVersionFile),
    ).writeAsString(version, flush: true);
  }

  static String? _zashboardEntryPath(String targetDirPath, String name) {
    // Strip the single top-level dist/ directory the release zip carries.
    var relative = name.replaceAll('\\', '/');
    if (relative.startsWith('dist/')) {
      relative = relative.substring('dist/'.length);
    }
    final normalized = posix.normalize(relative);
    if (normalized.isEmpty ||
        posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      return null;
    }
    final outPath = normalize(join(targetDirPath, normalized));
    if (!isWithin(targetDirPath, outPath)) {
      return null;
    }
    return outPath;
  }

  Future<void> init(int version) async {
    await ensureHomeDir();
    await initGeo();
    await initZashboard();
    final homeDirPath = await appPath.homeDirPath;
    await _interface.init(InitParams(homeDir: homeDirPath, version: version));
  }

  /// An age-encrypted config is rewritten in place into its plaintext, and a
  /// share-link list into a config of its proxies.
  Future<String?> validateProfile(
    String path, [
    String ageSecretKey = '',
  ]) async {
    final file = File(path);
    if (await file.isAgeEncrypted) {
      if (ageSecretKey.isEmpty) {
        throw const AgeSecretKeyRequiredException();
      }
      await file.safeWriteAsString(
        await _interface.decryptConfig(path, ageSecretKey),
      );
    }
    final issue = await _interface.validateConfig(path);
    if (issue == null) {
      return null;
    }
    final List<Map<String, dynamic>> proxies;
    try {
      proxies = await _interface.convertProxies(path);
    } on Exception {
      return issue;
    }
    if (proxies.isEmpty) {
      return issue;
    }
    await file.safeWriteAsString(await encodeYamlTask({'proxies': proxies}));
    return _interface.validateConfig(path);
  }

  Future<Map<int, String>> validateProxies(List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) {
      return Future.value(const {});
    }
    return _interface.validateProxies(proxies);
  }

  Future<Map<int, String>> validateFilters(List<String> filters) {
    if (filters.isEmpty) {
      return Future.value(const {});
    }
    return _interface.validateFilters(filters);
  }

  Future<List<String>> encodeShareLinks(List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) {
      return Future.value(const []);
    }
    return _interface.encodeShareLinks(proxies);
  }

  Future<List<List<Map<String, dynamic>>>> decodeShareLinks(
    List<String> lines,
  ) {
    if (lines.isEmpty) {
      return Future.value(const []);
    }
    return _interface.decodeShareLinks(lines);
  }

  Future<String?> validateConfigWithData(List<int> data) async {
    final path = await appPath.tempFilePath;
    final file = File(path);
    await file.safeWriteAsBytes(data);
    try {
      return await _interface.validateConfig(path);
    } finally {
      await file.safeDelete();
    }
  }

  Future<void> setupConfig({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
  }) async {
    if (preloadInvoke == null) {
      return _interface.setupConfig(params);
    }
    await (_interface.setupConfig(params), preloadInvoke()).wait;
  }

  Future<List<Group>> getProxiesGroups({
    required ProxiesSortType sortType,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String defaultTestUrl,
  }) async {
    final proxiesData = await _interface.getProxies();
    return toGroupsTask(
      ComputeGroupsState(
        proxiesData: proxiesData,
        sortType: sortType,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
    );
  }

  Future<Map<String, dynamic>> readConfig(int id) async {
    final path = await appPath.getProfilePath(id.toString());
    final data = await _interface.readConfig(path);
    data['rules'] = data['rule'];
    data.remove('rule');
    return data;
  }

  Future<Map<String, dynamic>> getProfileOutbounds(int id) async {
    return _interface.getProfileOutbounds(
      await appPath.getProfilePath(id.toString()),
    );
  }

  Future<String> buildProfile(SetupBase base) async {
    return readSpilledText(await _interface.buildProfile(base));
  }

  Future<({ProfileBase base, String path})> getProfileBase(int id) async {
    final path = await appPath.getProfilePath(id.toString());
    final base = await _interface.getProfileBase(path);
    final config = Map<String, dynamic>.from(base.config)..remove('rule');
    return (base: base.copyWith(config: config), path: path);
  }
}

final coreController = CoreController();
