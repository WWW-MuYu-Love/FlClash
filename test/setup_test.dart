import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {
        'APP_ENV': 'dev',
        'FEATURE_MITM': 'true',
      });
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    test('refuses to package while a native build hook is skipped', () {
      const pubspec = '''
hooks:
  user_defines:
    setup:
      build_assets: false
    rust_api:
      build_assets: true
''';

      expect(setup.packagesNotBuildingAssets(pubspec), ['setup']);
      expect(setup.packagesNotBuildingAssets('name: x\n'), isEmpty);
    });

    test('packages every Linux format on every architecture', () {
      expect(setup.createPackageTargets('linux', null), 'deb,appimage,rpm');
      expect(setup.createPackageTargets('linux', 'deb'), 'deb');
      expect(setup.createPackageTargets('macos', null), 'dmg');
      expect(setup.createPackageTargets('ios', null), 'ipa');
    });

    test('parses iOS bundle identifier override', () {
      final results = setup.createSetupArgParser().parse([
        'ios',
        '--ios-bundle-id',
        'love.muyu.flclash',
      ]);

      expect(results['ios-bundle-id'], 'love.muyu.flclash');
      expect(results.rest, ['ios']);
    });

    test('parses unsigned iOS packaging mode', () {
      final results = setup.createSetupArgParser().parse([
        'ios',
        '--no-codesign',
      ]);

      expect(results['no-codesign'], isTrue);
      expect(results.rest, ['ios']);
    });

    test('derives no-sign signing targets from their names', () {
      final targets = setup.createIOSNoSignSigningTargets(
        rootDir: p.join('workspace', 'flclash'),
        appBundlePath: p.join('build', 'Runner.app'),
        appBundleId: 'love.muyu.flclash',
      );

      expect(targets, [
        (
          bundle: p.join('build', 'Runner.app', 'PlugIns', 'NECore.appex'),
          bundleIdentifier: 'love.muyu.flclash.NECore',
          entitlements: p.join(
            'workspace',
            'flclash',
            'ios',
            'NECore',
            'NECore.entitlements',
          ),
        ),
        (
          bundle: p.join('build', 'Runner.app', 'PlugIns', 'Widget.appex'),
          bundleIdentifier: 'love.muyu.flclash.Widget',
          entitlements: p.join(
            'workspace',
            'flclash',
            'ios',
            'Widget',
            'Widget.entitlements',
          ),
        ),
        (
          bundle: p.join('build', 'Runner.app'),
          bundleIdentifier: 'love.muyu.flclash',
          entitlements: p.join(
            'workspace',
            'flclash',
            'ios',
            'Runner',
            'Runner.entitlements',
          ),
        ),
      ]);
    });

    test('substitutes bundle id and team into no-sign entitlements', () {
      const source = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.\\\$(APP_BUNDLE_ID)</string>
  </array>
</dict>
</plist>
''';

      final content = setup.createIOSNoSignEntitlements(
        source: source,
        appBundleId: 'love.muyu.flclash',
        bundleIdentifier: 'love.muyu.flclash.NECore',
        teamIdentifier: 'ABCDE12345',
      );
      final document = XmlDocument.parse(content);
      final elements = document.rootElement
          .getElement('dict')!
          .childElements
          .toList();
      final values = <String, String>{};
      for (var index = 0; index + 1 < elements.length; index++) {
        if (elements[index].name.local == 'key') {
          values[elements[index].innerText] = elements[index + 1].innerText
              .trim();
        }
      }

      expect(
        values['application-identifier'],
        'ABCDE12345.love.muyu.flclash.NECore',
      );
      expect(values['com.apple.developer.team-identifier'], 'ABCDE12345');
      expect(
        values['com.apple.security.application-groups'],
        'group.love.muyu.flclash',
      );
    });

    test('falls back to unknown when replacing identity entitlements', () {
      const source = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>application-identifier</key>
  <string>OLD.identifier</string>
  <key>com.apple.developer.team-identifier</key>
  <string>OLDTEAM</string>
</dict>
</plist>
''';

      final content = setup.createIOSNoSignEntitlements(
        source: source,
        appBundleId: 'love.muyu.flclash',
        bundleIdentifier: 'love.muyu.flclash',
      );

      expect(
        RegExp('<key>application-identifier</key>').allMatches(content),
        hasLength(1),
      );
      expect(content, contains('UNKNOWN000.love.muyu.flclash'));
      expect(
        content,
        contains(
          '<key>com.apple.developer.team-identifier</key>\n'
          '\t\t<string>UNKNOWN000</string>',
        ),
      );
      expect(content, isNot(contains('OLD.identifier')));
      expect(content, isNot(contains('OLDTEAM')));
    });

    test('writes generated iOS bundle config', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'flclash_setup_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await setup.writeIOSGeneratedBundleConfig(
        tempDir.path,
        'love.muyu.flclash',
        'ABCDE12345',
      );

      final configFile = File(
        p.join(
          tempDir.path,
          'ios',
          'Flutter',
          'GeneratedBundleConfig.xcconfig',
        ),
      );
      final content = await configFile.readAsString();
      expect(content, contains('APP_BUNDLE_ID = love.muyu.flclash'));
      expect(content, contains('DEVELOPMENT_TEAM = ABCDE12345'));
    });

    test('adds default iOS export method to flutter build args', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'ios',
        verbose: false,
      );

      expect(args, [
        'dart-define-from-file=env.json',
        'export-method=app-store',
      ]);
    });

    test('uses iOS export options plist when provided', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'ios',
        verbose: false,
        iosExportOptionsPlist: 'ios/ExportOptions.plist',
      );

      expect(args, [
        'dart-define-from-file=env.json',
        'export-options-plist=ios/ExportOptions.plist',
      ]);
    });

    test('downloads the appimagetool build matching the host', () {
      expect(setup.appImageToolArch('arm64'), 'aarch64');
      expect(setup.appImageToolArch('amd64'), 'x86_64');
    });
  });
}
