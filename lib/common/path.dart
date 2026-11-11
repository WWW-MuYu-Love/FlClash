import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';

/// iOS: the NECore extension can only read the shared App Group container,
/// so the data directory moves there, copying any files the app already
/// wrote under its own support directory first.
@visibleForTesting
Future<Directory> migrateIOSDataDirectory({
  required Directory supportDirectory,
  required String appGroupPath,
}) async {
  if (appGroupPath.isEmpty) {
    return supportDirectory;
  }
  final appGroupDirectory = Directory(appGroupPath);
  await appGroupDirectory.create(recursive: true);
  if (!await supportDirectory.exists() ||
      equals(supportDirectory.path, appGroupDirectory.path)) {
    return appGroupDirectory;
  }
  await for (final entity in supportDirectory.list(recursive: true)) {
    final targetPath = join(
      appGroupDirectory.path,
      relative(entity.path, from: supportDirectory.path),
    );
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File && !await File(targetPath).exists()) {
      await File(targetPath).parent.create(recursive: true);
      await entity.copy(targetPath);
    }
  }
  return appGroupDirectory;
}

/// App Groups listed in the install's own provisioning profile, read
/// natively: every install is signed with its own groups, so the
/// identifier differs per device and certificate. Empty when the channel
/// is unavailable (non-iOS, or before the engine is ready); the caller
/// then only tries the derived group.
@visibleForTesting
Future<List<String>> profileAppGroups() async {
  try {
    const channel = MethodChannel('$packageName/service');
    final groups = await channel.invokeMethod<List<dynamic>>(
      'getProfileAppGroups',
    );
    return groups?.map((group) => group.toString()).toList() ?? [];
  } catch (_) {
    return [];
  }
}

/// Resolves the iOS App Group container path: the group derived from the
/// bundle ID first, then the groups from the provisioning profile in
/// order (SideKite renames the bundle ID at install, so the derived
/// group never resolves on a SideKite install). Returns '' when none
/// resolves, and the caller falls back to the app's own support
/// directory. Without a shared group both the app and the extension
/// fall back to their own private containers, so the extension core
/// cannot serve the bundled zashboard from the app's container: its
/// IsSafePath check rejects paths outside its own home.
@visibleForTesting
Future<String> resolveIOSAppGroupPath({
  required String packageName,
  required List<String> profileAppGroups,
  required Future<String?> Function(String appGroupIdentifier) getContainerPath,
}) async {
  for (final identifier in ['group.$packageName', ...profileAppGroups]) {
    final path = await getContainerPath(identifier);
    if (path != null && path.isNotEmpty) {
      return path;
    }
  }
  return '';
}

class AppPath {
  static AppPath? _instance;
  late ResolveOnce<Directory> _dataDir;
  late ResolveOnce<Directory?> _downloadDir;
  late ResolveOnce<Directory> _tempDir;
  Completer<Directory> cacheDir = Completer();

  @visibleForTesting
  static Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory;

  @visibleForTesting
  static Future<Directory> Function() temporaryDirectory =
      getTemporaryDirectory;

  @visibleForTesting
  static Future<Directory> Function() cacheDirectory =
      getApplicationCacheDirectory;

  @visibleForTesting
  static Future<Directory?> Function() downloadDirectory =
      getDownloadsDirectory;

  AppPath._internal() {
    _bind();
  }

  @visibleForTesting
  Future<void> rebind() async {
    cacheDir = Completer();
    _bind();
    await Future.wait([_dataDir.value, _downloadDir.value, _tempDir.value]);
  }

  void _bind() {
    _dataDir = ResolveOnce(() async {
      final support = await supportDirectory();
      if (!system.isIOS) return support;
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        final appGroupPath = await resolveIOSAppGroupPath(
          packageName: packageInfo.packageName,
          profileAppGroups: await profileAppGroups(),
          getContainerPath: (identifier) => PathProviderFoundation()
              .getContainerPath(appGroupIdentifier: identifier),
        );
        return await migrateIOSDataDirectory(
          supportDirectory: support,
          appGroupPath: appGroupPath,
        );
      } catch (_) {
        return support;
      }
    });
    _downloadDir = ResolveOnce(downloadDirectory);
    _tempDir = ResolveOnce(temporaryDirectory);
    cacheDirectory().then(cacheDir.complete);
  }

  factory AppPath() {
    _instance ??= AppPath._internal();
    return _instance!;
  }

  String get executableExtension {
    return system.isWindows ? '.exe' : '';
  }

  String get executableDirPath {
    final currentExecutablePath = Platform.resolvedExecutable;
    return dirname(currentExecutablePath);
  }

  String get corePath {
    return join(executableDirPath, 'FlClashCore$executableExtension');
  }

  String get helperPath {
    return join(executableDirPath, '$appHelperService$executableExtension');
  }

  Future<String> get downloadDirPath async {
    final directory = await _downloadDir.value;
    return directory?.path ?? await homeDirPath;
  }

  Future<String> get homeDirPath async {
    final directory = await _dataDir.value;
    return directory.path;
  }

  Future<String> get databasePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'database.sqlite');
  }

  Future<String> get tempFilePath async {
    final mTempDir = await _tempDir.value;
    return join(mTempDir.path, 'temp$uniqueId');
  }

  /// On Android the app's external downloads directory, the one the system
  /// download manager can write to.
  Future<String> get updateDirPath async {
    final directory = system.isAndroid
        ? await downloadDirPath
        : (await cacheDir.future).path;
    return join(directory, 'update');
  }

  Future<String> get lockFilePath async {
    final homeDirPath = await appPath.homeDirPath;
    return join(homeDirPath, 'FlClash.lock');
  }

  Future<String> get configFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'config.yaml');
  }

  Future<String> get sharedPreferencesPath async {
    final directory = await _dataDir.value;
    return join(directory.path, 'shared_preferences.json');
  }

  Future<String> get profilesPath async {
    final directory = await _dataDir.value;
    return join(directory.path, profilesDirectoryName);
  }

  Future<String> getProfilePath(String fileName) async {
    return join(await profilesPath, '$fileName.yaml');
  }

  Future<String> get scriptsDirPath async {
    final path = await homeDirPath;
    return join(path, 'scripts');
  }

  Future<String> getScriptPath(String fileName) async {
    return scriptPathIn(await scriptsDirPath, fileName);
  }

  static String scriptPathIn(String scriptsDir, String fileName) {
    return join(scriptsDir, '$fileName.js');
  }

  Future<String> get mitmModulesDirPath async {
    return join(await homeDirPath, mitmDirectoryName, mitmModulesDirectoryName);
  }

  /// Captures the core persists under `<home>/mitm/captures/`. On iOS the
  /// home directory is the shared App Group container, so the app reads
  /// the extension core's captures from here without asking it.
  Future<String> get mitmCapturesDirPath async {
    return join(await homeDirPath, mitmDirectoryName, 'captures');
  }

  Future<String> get mitmResourcesDirPath async {
    return join(
      await homeDirPath,
      mitmDirectoryName,
      mitmResourcesDirectoryName,
    );
  }

  Future<String> get providerCacheRootPath async {
    final directory = await homeDirPath;
    return join(directory, providersDirectoryName);
  }

  Future<String> get ruleProviderCacheDirPath async {
    return join(await providerCacheRootPath, rulesProviderDirectoryName);
  }

  Future<String> getProviderCachePath(String fileName) async {
    return join(await ruleProviderCacheDirPath, fileName);
  }

  Future<String> getProvidersRootPath() async {
    final directory = await profilesPath;
    return join(directory, providersDirectoryName);
  }

  Future<String> getProviderDirPath(int profileId, String type) async {
    final directory = await getProvidersRootPath();
    return join(directory, profileId.toString(), type);
  }

  Future<void> ensureProviderDirs(int profileId) async {
    for (final type in const [
      proxiesProviderDirectoryName,
      rulesProviderDirectoryName,
    ]) {
      final directory = Directory(await getProviderDirPath(profileId, type));
      if (await directory.exists()) {
        continue;
      }
      await directory.create(recursive: true);
    }
  }

  Future<String> get tempPath async {
    final directory = await _tempDir.value;
    return directory.path;
  }
}

final appPath = AppPath();

String getBackupFileName() {
  return '${appName}_backup_${DateTime.now().show}.zip';
}

String get logFileName {
  return '${appName}_${DateTime.now().show}.log';
}
