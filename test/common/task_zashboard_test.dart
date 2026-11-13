import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'makeRealProfileTask points external-ui at the bundled zashboard dir',
    () async {
      final result = await makeRealProfileTask(
        const MakeRealProfileState(
          profilesPath: '/home/profiles',
          profileId: 7,
          rawConfig: {},
          realPatchConfig: PatchClashConfig(),
          appendSystemDns: false,
          proxyGroups: [],
          rules: [],
          addedRules: [],
          defaultUA: 'FlClash-Test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;

      // Relative so each core resolves it against its own home.
      expect(config['external-ui'], 'ui/zashboard');
      expect(config['external-ui-name'], '');
      expect(config['external-ui-url'], '');
    },
  );
}
