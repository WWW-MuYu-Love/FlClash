import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('path_test');
    await useAppPaths(root);
  });

  tearDownAll(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('provider directories match the paths handed to the core', () async {
    const proxiesUrl = 'https://example.com/a.yaml';
    const rulesUrl = 'https://example.com/b.yaml';
    final proxiesDir = await appPath.getProviderDirPath(
      7,
      proxiesProviderDirectoryName,
    );
    final rulesDir = await appPath.getProviderDirPath(
      7,
      rulesProviderDirectoryName,
    );

    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: await appPath.profilesPath,
        profileId: 7,
        rawConfig: {
          'proxy-providers': {
            'a': {'type': 'http', 'url': proxiesUrl},
          },
          'rule-providers': {
            'b': {'type': 'http', 'url': rulesUrl},
          },
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;

    expect(
      config['proxy-providers']['a']['path'],
      join(proxiesDir, 'a@$proxiesUrl'.toMd5()),
    );
    expect(
      config['rule-providers']['b']['path'],
      join(rulesDir, 'b@$rulesUrl'.toMd5()),
    );
  });

  test('confines a provider path the profile tried to choose', () async {
    final proxiesDir = await appPath.getProviderDirPath(
      7,
      proxiesProviderDirectoryName,
    );
    final rulesDir = await appPath.getProviderDirPath(
      7,
      rulesProviderDirectoryName,
    );

    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: await appPath.profilesPath,
        profileId: 7,
        rawConfig: {
          'proxy-providers': {
            'escape': {'type': 'file', 'path': '../../../../config.yaml'},
            'urlless': {'type': 'http', 'path': 'cache.db'},
            'literal': {
              'type': 'inline',
              'payload': ['DIRECT'],
            },
          },
          'rule-providers': {
            'sneak': {'type': 'file', 'path': '/etc/hosts'},
          },
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash',
      ),
    );
    final config = loadYaml(result.yaml) as YamlMap;

    expect(
      config['proxy-providers']['escape']['path'],
      join(proxiesDir, 'proxy-providers/escape'.toMd5()),
    );
    expect(
      config['proxy-providers']['urlless']['path'],
      join(proxiesDir, 'proxy-providers/urlless'.toMd5()),
    );
    expect(config['proxy-providers']['literal']['path'], isNull);
    expect(
      config['rule-providers']['sneak']['path'],
      join(rulesDir, 'rule-providers/sneak'.toMd5()),
    );
  });

  test('survives a provider section that is not a map', () async {
    final result = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: await appPath.profilesPath,
        profileId: 7,
        rawConfig: {
          'proxy-providers': ['not-a-map'],
          'rule-providers': {
            'broken': ['also-not-a-map'],
          },
        },
        realPatchConfig: const PatchClashConfig(),
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash',
      ),
    );

    expect(result.yaml, isNotEmpty);
  });

  test('ensureProviderDirs creates both provider directories', () async {
    await appPath.ensureProviderDirs(9);

    for (final type in const [
      proxiesProviderDirectoryName,
      rulesProviderDirectoryName,
    ]) {
      expect(
        Directory(await appPath.getProviderDirPath(9, type)).existsSync(),
        isTrue,
      );
    }

    await expectLater(appPath.ensureProviderDirs(9), completes);
  });

  test('syncs the MITM CA and resources into the FlClash folder', () async {
    final home = Directory(join(root.path, 'sync-home'))..createSync();
    final group = Directory(join(root.path, 'sync-group'))..createSync();
    final mitmDir = Directory(join(home.path, mitmDirectoryName))..createSync();
    File(join(mitmDir.path, mitmCaCertFileName)).writeAsStringSync('cert');
    File(join(mitmDir.path, mitmCaKeyFileName)).writeAsStringSync('key');
    final resourcesDir = Directory(
      join(mitmDir.path, mitmResourcesDirectoryName),
    )..createSync();
    File(join(resourcesDir.path, 'local.txt')).writeAsStringSync('resource');
    File(join(home.path, 'config.yaml')).writeAsStringSync('config');

    await syncIOSSharedFiles(homeDir: home, appGroupPath: group.path);

    final sharedMitmDir = Directory(
      join(group.path, sharedFlClashDirectoryName, mitmDirectoryName),
    );
    expect(
      File(join(sharedMitmDir.path, mitmCaCertFileName)).readAsStringSync(),
      'cert',
    );
    expect(
      File(join(sharedMitmDir.path, mitmCaKeyFileName)).readAsStringSync(),
      'key',
    );
    expect(
      File(
        join(sharedMitmDir.path, mitmResourcesDirectoryName, 'local.txt'),
      ).readAsStringSync(),
      'resource',
    );
    expect(
      File(
        join(group.path, sharedFlClashDirectoryName, 'config.yaml'),
      ).existsSync(),
      isFalse,
    );
  });

  test('removes shared files whose private source is gone', () async {
    final home = Directory(join(root.path, 'prune-home'))..createSync();
    final group = Directory(join(root.path, 'prune-group'))..createSync();
    final sharedResourcesDir = Directory(
      join(
        group.path,
        sharedFlClashDirectoryName,
        mitmDirectoryName,
        mitmResourcesDirectoryName,
      ),
    )..createSync(recursive: true);
    File(join(sharedResourcesDir.path, 'stale.txt')).writeAsStringSync('stale');

    await syncIOSSharedFiles(homeDir: home, appGroupPath: group.path);

    expect(sharedResourcesDir.existsSync(), isFalse);
  });

  test('does nothing when no iOS app-group is available', () async {
    final home = Directory(join(root.path, 'nogroup-home'))..createSync();

    await expectLater(
      syncIOSSharedFiles(homeDir: home, appGroupPath: ''),
      completes,
    );
  });

  test('the shared iOS dir is null where there is no app group', () async {
    // Tests run off iOS, so there is no App Group container to share.
    expect(await appPath.sharedIOSFlClashDirPath, isNull);
  });

  test('resolves the app group derived from the bundle id', () async {
    const derivedPath = '/groups/derived';
    const profilePath = '/groups/profile';

    final resolved = await resolveIOSAppGroupPath(
      packageName: 'love.muyu.flclash',
      profileAppGroups: const ['group.e6c8545ed2c36db3.1'],
      getContainerPath: (identifier) async {
        return switch (identifier) {
          'group.love.muyu.flclash' => derivedPath,
          'group.e6c8545ed2c36db3.1' => profilePath,
          _ => null,
        };
      },
    );

    expect(resolved, derivedPath);
  });

  test(
    'falls back to a profile group when the derived group is missing',
    () async {
      const profilePath = '/groups/profile';

      final resolved = await resolveIOSAppGroupPath(
        packageName: 'renamed.by.sidekite',
        profileAppGroups: const ['group.e6c8545ed2c36db3.1'],
        getContainerPath: (identifier) async {
          return switch (identifier) {
            'group.e6c8545ed2c36db3.1' => profilePath,
            _ => null,
          };
        },
      );

      expect(resolved, profilePath);
    },
  );

  test(
    'falls back to a profile group when the derived group is empty',
    () async {
      const profilePath = '/groups/profile';

      final resolved = await resolveIOSAppGroupPath(
        packageName: 'renamed.by.sidekite',
        profileAppGroups: const ['group.e6c8545ed2c36db3.1'],
        getContainerPath: (identifier) async {
          return switch (identifier) {
            'group.renamed.by.sidekite' => '',
            'group.e6c8545ed2c36db3.1' => profilePath,
            _ => null,
          };
        },
      );

      expect(resolved, profilePath);
    },
  );

  test('tries profile groups in order', () async {
    const secondPath = '/groups/second';

    final resolved = await resolveIOSAppGroupPath(
      packageName: 'renamed.by.sidekite',
      profileAppGroups: const [
        'group.e6c8545ed2c36db3.1',
        'group.e6c8545ed2c36db3.2',
      ],
      getContainerPath: (identifier) async {
        return switch (identifier) {
          'group.e6c8545ed2c36db3.2' => secondPath,
          _ => null,
        };
      },
    );

    expect(resolved, secondPath);
  });

  test('returns empty when neither app group resolves', () async {
    final resolved = await resolveIOSAppGroupPath(
      packageName: 'renamed.by.sidekite',
      profileAppGroups: const [],
      getContainerPath: (_) async => null,
    );

    expect(resolved, isEmpty);
  });
}
