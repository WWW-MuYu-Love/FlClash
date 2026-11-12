import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

const _allTargets = <String, String>{
  'android': 'apk',
  'ios': 'ipa',
  'linux': 'deb,appimage,rpm',
  'macos': 'dmg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'windows': 'windows',
};

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host &&
      platform != 'android' &&
      !(host == 'macos' && platform == 'ios')) {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android'
      '${host == 'macos' ? ', ios' : ''}',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final rootDir = Directory.current.path;
  final skipped = packagesNotBuildingAssets(
    File(p.join(rootDir, 'pubspec.yaml')).readAsStringSync(),
  );
  if (skipped.isNotEmpty) {
    stderr.writeln(
      'pubspec.yaml sets hooks.user_defines.<package>.build_assets: false '
      'for ${skipped.join(', ')}; a package built this way would ship '
      'whatever is left in libclash/ and no Rust library. '
      'Restore "build_assets: true".',
    );
    exit(1);
  }
  final arch = _detectArch();
  final targets = createPackageTargets(platform, results['targets']);
  final androidArch = results['arch'] as String?;
  final verbose = results['verbose'] as bool;
  final iosExportMethod = results['ipa-export-method'] as String;
  final iosExportOptionsPlist = results['ipa-export-options-plist'] as String?;
  final iosBundleId = results['ios-bundle-id'] as String?;
  final iosDevelopmentTeam = results['ios-development-team'] as String?;
  final iosNoSign = results['no-codesign'] as bool;

  if (iosNoSign && platform != 'ios') {
    stderr.writeln('--no-codesign is only supported for iOS builds.');
    exit(64);
  }
  if (platform == 'ios' && androidArch != null) {
    stderr.writeln('--arch is not used for iOS; the package is arm64.');
    exit(64);
  }

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    iosExportMethod: iosExportMethod,
    iosExportOptionsPlist: iosExportOptionsPlist,
    iosBundleId: iosBundleId,
    iosDevelopmentTeam: iosDevelopmentTeam,
    iosNoSign: iosNoSign,
    verbose: verbose,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'pre',
      allowed: ['dev', 'pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,dmg,apk,...',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help: 'Target architecture (Android only)',
    )
    ..addOption(
      'ipa-export-method',
      defaultsTo: 'ad-hoc',
      allowed: ['app-store', 'ad-hoc', 'development', 'enterprise'],
      help: 'iOS IPA export method',
    )
    ..addOption(
      'ipa-export-options-plist',
      valueHelp: 'ios/ExportOptions.plist',
      help: 'iOS IPA export options plist',
    )
    ..addOption(
      'ios-bundle-id',
      valueHelp: 'love.muyu.flclash',
      help: 'Override iOS Runner bundle identifier for CI builds',
    )
    ..addOption(
      'ios-development-team',
      valueHelp: 'XXXXXXXXXX',
      help: 'Override iOS development team for CI builds',
    )
    ..addFlag(
      'no-codesign',
      negatable: false,
      help: 'Build an IPA without Apple provisioning (iOS only)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    );
}

List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
  String? iosExportMethod,
  String? iosExportOptionsPlist,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
  }
  if (platform == 'ios') {
    if (iosExportOptionsPlist != null && iosExportOptionsPlist.isNotEmpty) {
      flutterBuildArgs.add('export-options-plist=$iosExportOptionsPlist');
    } else {
      flutterBuildArgs.add('export-method=${iosExportMethod ?? 'ad-hoc'}');
    }
  }
  return flutterBuildArgs;
}

Map<String, String> createBuildEnvironment(String env) {
  return {
    'APP_ENV': env,
    // The MITM UI (Tools -> Advanced config -> MITM) is gated by this
    // compile-time flag; the core MITM engine is already integrated, so
    // the iOS build ships with the UI enabled.
    'FEATURE_MITM': 'true',
  };
}

/// Packages whose build hook `pubspec.yaml` turns into a no-op.
List<String> packagesNotBuildingAssets(String pubspec) {
  final document = loadYaml(pubspec);
  if (document is! Map) return const [];
  final defines = (document['hooks'] as Map?)?['user_defines'];
  if (defines is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in defines.entries)
      if (value is Map && value['build_assets'] == false) key.toString(),
  ]..sort();
}

String createPackageTargets(String platform, String? customTargets) {
  return customTargets ?? _allTargets[platform]!;
}

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln(
    'Platform: current host platform (default), android, or ios (on macOS)',
  );
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  String? iosExportMethod,
  String? iosExportOptionsPlist,
  String? iosBundleId,
  String? iosDevelopmentTeam,
  bool iosNoSign = false,
  required bool verbose,
}) async {
  final file = File(p.join(rootDir, 'env.json'));
  await file.writeAsString(jsonEncode(createBuildEnvironment(env)));

  if (platform == 'ios') {
    await writeIOSGeneratedBundleConfig(
      rootDir,
      iosBundleId,
      iosNoSign ? null : iosDevelopmentTeam,
    );
  }

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
    iosExportMethod: iosExportMethod,
    iosExportOptionsPlist: iosExportOptionsPlist,
  );
  final descriptionArgs = <String>[];
  if (platform != 'android') {
    descriptionArgs.addAll(['--description', arch]);
  }

  final depExit = await _ensureDependencies(platform);
  if (depExit != 0) return depExit;

  if (platform == 'ios' && iosNoSign) {
    return packageIOSNoSign(
      rootDir: rootDir,
      appBundleId: iosBundleId ?? 'love.muyu.flclash',
      iosDevelopmentTeam: iosDevelopmentTeam,
      verbose: verbose,
    );
  }

  final activateResult = await Process.run('dart', [
    'pub',
    'global',
    'activate',
    '-s',
    'git',
    'https://github.com/chen08209/flutter_distributor.git',
    '--git-ref',
    'v0.6.11-flclash.4',
    '--git-path',
    'packages/flutter_distributor',
  ]);
  if (activateResult.exitCode != 0) {
    stderr.write(activateResult.stderr);
    return activateResult.exitCode;
  }

  final process = await Process.start(
    'flutter_distributor',
    [
      'package',
      '--skip-clean',
      '--platform',
      platform,
      '--targets',
      targets,
      if (androidArch != null)
        '--build-target-platform=${_androidFlutterTarget[androidArch]!}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: true,
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  return exitCode;
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<int> packageIOSNoSign({
  required String rootDir,
  required String appBundleId,
  String? iosDevelopmentTeam,
  required bool verbose,
}) async {
  final process = await Process.start('flutter', [
    if (verbose) '--verbose',
    'build',
    'ios',
    '--release',
    '--no-codesign',
    '--dart-define-from-file=env.json',
  ], workingDirectory: rootDir);
  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final buildExit = await process.exitCode;
  if (buildExit != 0) return buildExit;

  final appDir = Directory(
    p.joinAll([rootDir, 'build', 'ios', 'iphoneos', 'Runner.app']),
  );
  if (!await appDir.exists()) {
    stderr.writeln('iOS app bundle not found: ${appDir.path}');
    return 1;
  }

  final tempDir = await Directory.systemTemp.createTemp('flclash_nosign_');
  try {
    final signingTargets = createIOSNoSignSigningTargets(
      rootDir: rootDir,
      appBundlePath: appDir.path,
      appBundleId: appBundleId,
    );

    for (final target in signingTargets) {
      final profile = File(p.join(target.bundle, 'embedded.mobileprovision'));
      if (await profile.exists()) {
        await profile.delete();
      }
    }

    final genericSignExit = await _adHocCodesign(appDir.path, deep: true);
    if (genericSignExit != 0) return genericSignExit;

    for (final target in signingTargets) {
      final source = File(target.entitlements);
      if (!await source.exists()) {
        stderr.writeln('Entitlements file not found: ${source.path}');
        return 1;
      }
      if (!await Directory(target.bundle).exists()) {
        stderr.writeln('iOS bundle not found: ${target.bundle}');
        return 1;
      }

      final output = File(
        p.join(tempDir.path, '${p.basename(target.bundle)}.entitlements'),
      );
      await output.writeAsString(
        createIOSNoSignEntitlements(
          source: await source.readAsString(),
          appBundleId: appBundleId,
          bundleIdentifier: target.bundleIdentifier,
          teamIdentifier: iosDevelopmentTeam,
        ),
      );
      final exitCode = await _adHocCodesign(
        target.bundle,
        entitlements: output.path,
      );
      if (exitCode != 0) return exitCode;
    }
    final payloadDir = Directory(p.join(tempDir.path, 'Payload'));
    await payloadDir.create();
    final copyResult = await Process.run('ditto', [
      appDir.path,
      p.join(payloadDir.path, 'Runner.app'),
    ]);
    if (copyResult.exitCode != 0) {
      stderr.write(copyResult.stderr);
      return copyResult.exitCode;
    }

    final pubspec = File(p.join(rootDir, 'pubspec.yaml')).readAsStringSync();
    final version =
        RegExp(
          r'^version:\s*([^\s+]+)',
          multiLine: true,
        ).firstMatch(pubspec)?.group(1) ??
        'unknown';
    final outputDir = Directory(p.join(rootDir, 'dist'));
    await outputDir.create(recursive: true);
    final output = File(
      p.join(outputDir.path, 'FlClash-$version-ios-arm64-unsigned.ipa'),
    );
    if (await output.exists()) {
      await output.delete();
    }

    final packageResult = await Process.run('ditto', [
      '-c',
      '-k',
      '--sequesterRsrc',
      '--keepParent',
      payloadDir.path,
      output.path,
    ]);
    if (packageResult.exitCode != 0) {
      stderr.write(packageResult.stderr);
      return packageResult.exitCode;
    }
    stdout.writeln('No-sign IPA: ${output.path}');
    return 0;
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

List<({String bundle, String bundleIdentifier, String entitlements})>
createIOSNoSignSigningTargets({
  required String rootDir,
  required String appBundlePath,
  required String appBundleId,
}) {
  const targetNames = ['NECore', 'Widget', 'Runner'];
  return [
    for (final name in targetNames)
      (
        bundle: name == 'Runner'
            ? appBundlePath
            : p.join(appBundlePath, 'PlugIns', '$name.appex'),
        bundleIdentifier: '$appBundleId${name == 'Runner' ? '' : '.$name'}',
        entitlements: p.join(rootDir, 'ios', name, '$name.entitlements'),
      ),
  ];
}

String createIOSNoSignEntitlements({
  required String source,
  required String appBundleId,
  required String bundleIdentifier,
  String? teamIdentifier,
}) {
  final document = XmlDocument.parse(
    source.replaceAll(r'$(APP_BUNDLE_ID)', appBundleId),
  );
  final dictionary = document.rootElement.getElement('dict');
  if (dictionary == null) {
    throw const FormatException('Entitlements plist is missing its dictionary');
  }

  void setString(String key, String value) {
    final elements = dictionary.childElements.toList();
    for (var index = 0; index + 1 < elements.length; index++) {
      final element = elements[index];
      if (element.name.local == 'key' && element.innerText == key) {
        elements[index + 1].replace(
          XmlElement(const XmlName.parts('string'), const [], [XmlText(value)]),
        );
        return;
      }
    }
    dictionary.children
      ..add(XmlElement(const XmlName.parts('key'), const [], [XmlText(key)]))
      ..add(
        XmlElement(const XmlName.parts('string'), const [], [XmlText(value)]),
      );
  }

  final normalizedTeamIdentifier = teamIdentifier?.trim();
  final resolvedTeamIdentifier =
      normalizedTeamIdentifier == null || normalizedTeamIdentifier.isEmpty
      ? 'UNKNOWN000'
      : normalizedTeamIdentifier;
  setString(
    'application-identifier',
    '$resolvedTeamIdentifier.$bundleIdentifier',
  );
  setString('com.apple.developer.team-identifier', resolvedTeamIdentifier);
  return document.toXmlString(pretty: true, indent: '\t');
}

Future<int> _adHocCodesign(
  String target, {
  String? entitlements,
  bool deep = false,
}) async {
  final result = await Process.run('codesign', [
    '--force',
    if (deep) '--deep',
    '--sign',
    '-',
    '--timestamp=none',
    if (entitlements != null) ...[
      '--generate-entitlement-der',
      '--entitlements',
      entitlements,
    ],
    target,
  ]);
  if (result.exitCode != 0) {
    stderr.write(result.stdout);
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<void> writeIOSGeneratedBundleConfig(
  String rootDir,
  String? iosBundleId,
  String? developmentTeam,
) async {
  final file = File(
    p.joinAll([rootDir, 'ios', 'Flutter', 'GeneratedBundleConfig.xcconfig']),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(
    [
      '// Generated by setup.dart. Do not edit.',
      if (iosBundleId != null) 'APP_BUNDLE_ID = $iosBundleId',
      if (developmentTeam != null) 'DEVELOPMENT_TEAM = $developmentTeam',
      '',
    ].join('\n'),
  );
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(which, args);
  return result.exitCode == 0;
}

({int major, int minor, int patch})? parseGoVersion(String output) {
  final match = RegExp(r'go(\d+)\.(\d+)\.(\d+)').firstMatch(output);
  if (match == null) return null;
  return (
    major: int.parse(match.group(1)!),
    minor: int.parse(match.group(2)!),
    patch: int.parse(match.group(3)!),
  );
}

/// mitmproxy-go requires Go >= 1.27.3 (see codemagic.yaml).
bool isSupportedGoVersion(({int major, int minor, int patch}) version) {
  if (version.major != 1) return version.major > 1;
  if (version.minor != 27) return version.minor > 27;
  return version.patch >= 3;
}

Future<int> _ensureGoRustToolchains() async {
  if (!await _hasCommand('go')) {
    stderr.writeln(
      'Go >= 1.27.3 is required to build the core but `go` was not found '
      'on PATH. Install it from https://go.dev/dl/ and retry.',
    );
    return 1;
  }
  final goVersionResult = await Process.run('go', ['version']);
  final goVersionOutput = goVersionResult.stdout as String;
  final goVersion = parseGoVersion(goVersionOutput);
  if (goVersion == null || !isSupportedGoVersion(goVersion)) {
    stderr.writeln(
      'Go >= 1.27.3 is required to build the core, found '
      '${goVersionOutput.trim()}. Upgrade Go and retry.',
    );
    return 1;
  }
  if (!await _hasCommand('cargo')) {
    stderr.writeln(
      'Cargo (Rust) is required to build the Rust helper but `cargo` was '
      'not found on PATH. Install it via rustup (https://rustup.rs/) '
      'and retry.',
    );
    return 1;
  }
  return 0;
}

Future<int> _ensureDependencies(String platform) async {
  final toolchainExit = await _ensureGoRustToolchains();
  if (toolchainExit != 0) return toolchainExit;
  switch (platform) {
    case 'macos':
      return _ensureMacosDependencies();
    case 'linux':
      return _ensureLinuxDependencies();
    default:
      return 0;
  }
}

Future<int> _ensureMacosDependencies() async {
  if (await _hasCommand('appdmg')) {
    stdout.writeln('appdmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing appdmg (DMG creator)...');
  final result = await Process.run('npm', ['install', '-g', 'appdmg']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<int> _ensureLinuxDependencies() async {
  const pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libsecret-1-dev'],
    ['locate'],
    ['rpm', 'patchelf'],
    ['libfuse2'],
  ];

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) return installExit;
    }
  }

  const appimagetool = '/usr/local/bin/appimagetool';
  if (File(appimagetool).existsSync()) {
    stdout.writeln('appimagetool already installed, skipping.');
    return 0;
  }
  stdout.writeln('Downloading appimagetool...');
  final downloadName =
      'appimagetool-${appImageToolArch(_detectArch())}.AppImage';
  final dlResult = await Process.run('wget', [
    '-O',
    appimagetool,
    'https://github.com/AppImage/AppImageKit/releases/download/continuous/$downloadName',
  ]);
  if (dlResult.exitCode != 0) {
    stderr.write(dlResult.stderr);
    return dlResult.exitCode;
  }
  await Process.run('chmod', ['+x', appimagetool]);
  return 0;
}

String appImageToolArch(String arch) {
  return arch == 'arm64' ? 'aarch64' : 'x86_64';
}

/// Ubuntu 24.04 ships libfuse2 under its time64 name, which `dpkg -s libfuse2` cannot see.
const _debianPackageAliases = <String, List<String>>{
  'libfuse2': ['libfuse2t64'],
};

Future<bool> _isDebianPackageInstalled(String pkg) async {
  for (final name in [pkg, ...?_debianPackageAliases[pkg]]) {
    final result = await Process.run('dpkg', ['-s', name]);
    if (result.exitCode == 0 &&
        (result.stdout as String).contains('Status: install ok installed')) {
      return true;
    }
  }
  return false;
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}
