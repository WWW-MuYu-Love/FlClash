import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/mitm_body.dart';
import 'package:fl_clash/features/connection/mitm_exchanges.dart';
import 'package:fl_clash/features/connection/tracker_info_item.dart';
import 'package:fl_clash/features/mitm/module_editor.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/mitm.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/about.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/views/backup_and_restore.dart';
import 'package:fl_clash/views/config/advanced.dart';
import 'package:fl_clash/views/config/dns.dart';
import 'package:fl_clash/views/config/filters.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/views/config/icon_sets.dart';
import 'package:fl_clash/views/config/providers.dart';
import 'package:fl_clash/views/config/mitm.dart';
import 'package:fl_clash/views/config/mitm_modules.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/views/config/ntp.dart';
import 'package:fl_clash/views/config/on_demand.dart';
import 'package:fl_clash/views/config/rules.dart';
import 'package:fl_clash/views/config/scripts.dart';
import 'package:fl_clash/views/config/sniffer.dart';
import 'package:fl_clash/views/config/tun.dart';
import 'package:fl_clash/views/config/user_agents.dart';
import 'package:fl_clash/views/dashboard/widgets/memory_info.dart';
import 'package:fl_clash/views/developer.dart';
import 'package:fl_clash/views/disclaimer.dart';
import 'package:fl_clash/views/hotkey.dart';
import 'package:fl_clash/views/profiles/custom/custom.dart';
import 'package:fl_clash/views/profiles/custom/custom_proxies.dart';
import 'package:fl_clash/views/profiles/custom/dialers.dart';
import 'package:fl_clash/views/profiles/custom/providers.dart';
import 'package:fl_clash/views/profiles/custom/rules.dart';
import 'package:fl_clash/views/profiles/edit.dart';
import 'package:fl_clash/views/profiles/extend/extend.dart';
import 'package:fl_clash/views/profiles/extend/standard.dart';
import 'package:fl_clash/views/profiles/preview.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:fl_clash/views/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pushes a restorable sub-page, recording it in the navigation path until
/// it pops. [onResult] runs with the value the page pops with.
Future<T?> pushRestorable<T>(
  BuildContext context,
  Widget child,
  String restorationId, {
  ValueChanged<dynamic>? onResult,
}) {
  NavigationRestorationHooks.onPush?.call(restorationId);
  final future = BaseNavigator.push<T>(context, child);
  future.then((result) {
    NavigationRestorationHooks.onPop?.call(restorationId);
    onResult?.call(result);
  });
  return future;
}

/// Reopens a sheet recorded in the navigation path. Returns true when the
/// descriptor is a sheet.
Future<bool> restoreSheet(
  BuildContext context,
  WidgetRef ref,
  String descriptor,
) async {
  if (descriptor == 'memoryDetail') {
    final initial = await readMemorySnapshot(ref);
    if (initial == null || !context.mounted) {
      return true;
    }
    NavigationRestorationHooks.onPush?.call(descriptor);
    unawaited(
      showSheet(
        context: context,
        builder: (_) => MemoryDetailSheet(initial: initial),
      ).then((_) {
        NavigationRestorationHooks.onPop?.call(descriptor);
      }),
    );
    return true;
  }
  if (descriptor.startsWith('connectionDetail:')) {
    final detail = await Preferences().getLastTrackerDetail();
    final rawTracker = detail['tracker'];
    final title = detail['title'];
    if (rawTracker is! Map<String, Object?> || title is! String) {
      return true;
    }
    final tracker = TrackerInfo.fromJson(rawTracker);
    if (!context.mounted) {
      return true;
    }
    showTrackerInfoDetail(context, tracker, title);
    return true;
  }
  if (descriptor.startsWith('mitmExchange:')) {
    final id = int.tryParse(descriptor.substring('mitmExchange:'.length));
    if (id == null) {
      return true;
    }
    final exchange = await ref.read(mitmExchangeProvider(id).future);
    if (exchange == null || !context.mounted) {
      return true;
    }
    NavigationRestorationHooks.onPush?.call(descriptor);
    unawaited(
      showInSheet<void>(context, builder: (_) => MitmExchangeView(id: id)).then(
        (_) {
          NavigationRestorationHooks.onPop?.call(descriptor);
        },
      ),
    );
    return true;
  }
  if (descriptor.startsWith('profileEdit:')) {
    final id = int.tryParse(descriptor.substring('profileEdit:'.length));
    final profile = id == null ? null : ref.read(profileProvider(id));
    if (profile == null) {
      return true;
    }
    NavigationRestorationHooks.onPush?.call(descriptor);
    unawaited(
      showExtend(
        context,
        builder: (_) => EditProfileView(profile: profile),
      ).then((_) {
        NavigationRestorationHooks.onPop?.call(descriptor);
      }),
    );
    return true;
  }
  return false;
}

/// Rebuilds a restorable sub-page from its descriptor, or null when the
/// descriptor is unknown or its target no longer exists. The returned
/// onResult saves the value the page pops with, mirroring the opening
/// row's onChanged.
RestorablePage? navigationPathPage(
  BuildContext context,
  WidgetRef ref,
  String descriptor,
) {
  return switch (descriptor) {
    'tools/general' => (page: const GeneralView(), onResult: null),
    'tools/general/onDemand' => (page: const OnDemandView(), onResult: null),
    'tools/general/userAgents' => (
      page: const UserAgentsView(),
      onResult: null,
    ),
    'tools/general/hosts' => (
      page: const HostsView(),
      onResult: _saveHosts(ref),
    ),
    'tools/theme' => (page: const ThemeView(), onResult: null),
    'tools/backup' => (page: const BackupAndRestore(), onResult: null),
    'tools/hotkey' => (page: const HotKeyView(), onResult: null),
    'tools/access' => (page: const AccessView(), onResult: null),
    'tools/disclaimer' => (page: const DisclaimerView(), onResult: null),
    'tools/about' => (page: const AboutView(), onResult: null),
    'tools/developer' => (page: const DeveloperView(), onResult: null),
    'tools/advanced' => (page: const AdvancedConfigView(), onResult: null),
    'tools/advanced/network' => (
      page: BaseScaffold(
        title: context.appLocalizations.network,
        body: const NetworkListView(),
      ),
      onResult: null,
    ),
    'tools/advanced/dns' => (page: const DnsView(), onResult: null),
    'tools/advanced/rules' => (page: const AddedRulesView(), onResult: null),
    'tools/advanced/scripts' => (page: const ScriptsView(), onResult: null),
    'tools/advanced/mitm' => (
      page: MitmView(isAndroid: system.isAndroid),
      onResult: null,
    ),
    'tools/advanced/mitm/capture' => (
      page: MitmCaptureView(isAndroid: system.isAndroid),
      onResult: null,
    ),
    'tools/advanced/mitm/hostname' => (
      page: const MitmHostnameView(),
      onResult: null,
    ),
    'tools/advanced/mitm/modules' => (
      page: const MitmModulesView(),
      onResult: null,
    ),
    'tools/advanced/customProxies' => (
      page: const CustomProxiesView(),
      onResult: null,
    ),
    'tools/advanced/providers' => (
      page: const ClashProvidersView(),
      onResult: null,
    ),
    'tools/advanced/filters' => (page: const FiltersView(), onResult: null),
    'tools/advanced/iconSets' => (page: const IconSetsView(), onResult: null),
    _ when descriptor.startsWith('toolItem:') => _toolItem(
      context,
      ref,
      descriptor.substring('toolItem:'.length),
    ),
    _ when descriptor.startsWith('tools/advanced/dns:') => _dnsPolicy(
      context,
      ref,
      descriptor.substring('tools/advanced/dns:'.length),
    ),
    _ when descriptor.startsWith('profileDns:') => _profileDnsPolicy(
      context,
      ref,
      descriptor.substring('profileDns:'.length),
    ),
    _ when descriptor.startsWith('sniffer:') => _snifferField(
      descriptor.substring('sniffer:'.length),
    ),
    _ when descriptor.startsWith('snifferView:') => _snifferView(
      descriptor.substring('snifferView:'.length),
    ),
    _ when descriptor.startsWith('mitmModule:') => _mitmModule(
      descriptor.substring('mitmModule:'.length),
    ),
    _ when descriptor.startsWith('mitmModuleLines:') => _mitmModuleLines(
      context,
      ref,
      descriptor.substring('mitmModuleLines:'.length),
    ),
    _ when descriptor.startsWith('mitmModuleIgnored:') => _mitmModuleIgnored(
      context,
      ref,
      descriptor.substring('mitmModuleIgnored:'.length),
    ),
    _ when descriptor.startsWith('iconSet:') => _iconSet(
      descriptor.substring('iconSet:'.length),
    ),
    _ when descriptor.startsWith('profileExtendRules:') => _profileExtendRules(
      descriptor.substring('profileExtendRules:'.length),
    ),
    _ when descriptor.startsWith('profileCustomNew:') => _profileCustomNew(
      descriptor.substring('profileCustomNew:'.length),
    ),
    _ when descriptor.startsWith('proxyProviderEdit:') => _proxyProviderEdit(
      ref,
      descriptor.substring('proxyProviderEdit:'.length),
    ),
    _ when descriptor.startsWith('providerPreview:') => _providerPreview(
      ref,
      descriptor.substring('providerPreview:'.length),
    ),
    _ when descriptor.startsWith('moduleEditor:') => _moduleEditor(
      context,
      ref,
      descriptor.substring('moduleEditor:'.length),
    ),
    _ when descriptor.startsWith('mitmBodyEditor:') => _mitmBodyEditor(
      descriptor.substring('mitmBodyEditor:'.length),
    ),
    _ when descriptor.startsWith('mitmBodyHex:') => _mitmBodyHex(
      descriptor.substring('mitmBodyHex:'.length),
    ),
    _ when descriptor.startsWith('clashProviderEditor:') =>
      _clashProviderEditor(
        context,
        ref,
        descriptor.substring('clashProviderEditor:'.length),
      ),
    _ when descriptor.startsWith('clashProviderPreview:') =>
      _clashProviderPreview(
        ref,
        descriptor.substring('clashProviderPreview:'.length),
      ),
    _ when descriptor.startsWith('scriptEditor:') => _scriptEditor(
      context,
      ref,
      descriptor.substring('scriptEditor:'.length),
    ),
    _ when descriptor.startsWith('profileFileEditor:') => _profileFileEditor(
      context,
      ref,
      descriptor.substring('profileFileEditor:'.length),
    ),
    _ when descriptor.startsWith('overrideList:') => _overrideListEdit(
      ref,
      descriptor.substring('overrideList:'.length),
    ),
    _ when descriptor.startsWith('networkList:') => _networkListEdit(
      ref,
      descriptor.substring('networkList:'.length),
    ),
    _ when descriptor.startsWith('profileExtend:') => _profileExtend(
      descriptor.substring('profileExtend:'.length),
    ),
    _ when descriptor.startsWith('profileCustom:') => _profileCustom(
      descriptor.substring('profileCustom:'.length),
    ),
    _ when descriptor.startsWith('profileCustomRules:') => _profileCustomRules(
      descriptor.substring('profileCustomRules:'.length),
    ),
    _ when descriptor.startsWith('profileCustomProviders:') =>
      _profileCustomProviders(
        descriptor.substring('profileCustomProviders:'.length),
      ),
    _ when descriptor.startsWith('profileDnsView:') => _profileDnsView(
      descriptor.substring('profileDnsView:'.length),
    ),
    _ when descriptor.startsWith('profileCustomMore:') => _profileCustomMore(
      descriptor.substring('profileCustomMore:'.length),
    ),
    _ when descriptor.startsWith('profileCustomDialers:') =>
      _profileCustomDialers(
        descriptor.substring('profileCustomDialers:'.length),
      ),
    _ when descriptor.startsWith('profileCustomNtp:') => _profileCustomNtp(
      descriptor.substring('profileCustomNtp:'.length),
    ),
    _ when descriptor.startsWith('profileCustomTun:') => _profileCustomTun(
      descriptor.substring('profileCustomTun:'.length),
    ),
    _ when descriptor.startsWith('profilePreview:') => _profilePreview(
      ref,
      descriptor.substring('profilePreview:'.length),
    ),
    _ => null,
  };
}

ValueChanged<dynamic> _saveHosts(WidgetRef ref) {
  return (value) {
    if (value is! Map<String, String>) {
      return;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(hosts: value));
  };
}

RestorablePage? _toolItem(
  BuildContext context,
  WidgetRef ref,
  String rawLabel,
) {
  final label = PageLabel.values
      .where((element) => element.name == rawLabel)
      .firstOrNull;
  if (label == null) {
    return null;
  }
  final item = ref
      .read(moreToolsSelectorStateProvider)
      .navigationItems
      .where((element) => element.label == label)
      .firstOrNull;
  if (item == null) {
    return null;
  }
  return (page: item.builder(context), onResult: null);
}

RestorablePage? _dnsPolicy(BuildContext context, WidgetRef ref, String rawKey) {
  final key = DnsOverrideKey.values
      .where((element) => element.name == rawKey)
      .firstOrNull;
  if (key == null) {
    return null;
  }
  return dnsPolicyPage(context, ref, key);
}

RestorablePage? _profileDnsPolicy(
  BuildContext context,
  WidgetRef ref,
  String rest,
) {
  final parts = rest.split(':');
  if (parts.length != 2) {
    return null;
  }
  final profileId = int.tryParse(parts[0]);
  final key = DnsOverrideKey.values
      .where((element) => element.name == parts[1])
      .firstOrNull;
  if (profileId == null || key == null) {
    return null;
  }
  return dnsPolicyPage(context, ref, key, profileId: profileId);
}

RestorablePage? _snifferField(String rest) {
  final parts = rest.split(':');
  if (parts.length != 2) {
    return null;
  }
  final profileId = int.tryParse(parts[0]);
  final key = SnifferOverrideKey.values
      .where((element) => element.name == parts[1])
      .firstOrNull;
  if (profileId == null || key == null) {
    return null;
  }
  return (page: snifferFieldView(profileId, key), onResult: null);
}

RestorablePage? _snifferView(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: SnifferView(id), onResult: null);
}

RestorablePage? _mitmModule(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: MitmModuleView(id: id), onResult: null);
}

RestorablePage? _mitmModuleLines(
  BuildContext context,
  WidgetRef ref,
  String rest,
) {
  final parts = rest.split(':');
  if (parts.length != 2) {
    return null;
  }
  final id = int.tryParse(parts[0]);
  if (id == null) {
    return null;
  }
  final page = mitmModuleLinesView(context, ref, id, parts[1]);
  if (page == null) {
    return null;
  }
  return (page: page, onResult: null);
}

RestorablePage? _mitmModuleIgnored(
  BuildContext context,
  WidgetRef ref,
  String rawId,
) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  final page = mitmModuleIgnoredView(context, ref, id);
  if (page == null) {
    return null;
  }
  return (page: page, onResult: null);
}

RestorablePage? _profileExtend(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: ExtendView(profileId: id), onResult: null);
}

RestorablePage? _profileCustom(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: CustomProfileView(profileId: id), onResult: null);
}

RestorablePage? _profileCustomRules(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: CustomRulesView(id), onResult: null);
}

RestorablePage? _profileCustomProviders(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: CustomProvidersView(id), onResult: null);
}

RestorablePage? _profileDnsView(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: DnsView.profile(id), onResult: null);
}

RestorablePage? _profileCustomMore(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (
    page: MoreSectionsView(id, showsTun: system.isDesktop),
    onResult: null,
  );
}

RestorablePage? _profileCustomDialers(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: CustomProxyDialersView(id), onResult: null);
}

RestorablePage? _profileCustomNtp(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: NtpView(id), onResult: null);
}

RestorablePage? _profileCustomTun(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: TunView(id), onResult: null);
}

RestorablePage? _profilePreview(WidgetRef ref, String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  final profiles = ref.read(profilesProvider);
  final profile = profiles.where((element) => element.id == id).firstOrNull;
  if (profile == null) {
    return null;
  }
  return (page: PreviewProfileView(profile: profile), onResult: null);
}

RestorablePage? _iconSet(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: IconSetPreviewView(id), onResult: null);
}

RestorablePage? _profileExtendRules(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: EditGlobalAddedRules(id), onResult: null);
}

RestorablePage? _profileCustomNew(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return (page: CustomProfileView(profileId: id, isNew: true), onResult: null);
}

RestorablePage? _proxyProviderEdit(WidgetRef ref, String rawName) {
  final name = Uri.decodeComponent(rawName);
  final provider = ref
      .read(providersProvider)
      .where((element) => element.name == name)
      .firstOrNull;
  if (provider == null) {
    return null;
  }
  final path = provider.path;
  if (path == null || path.isEmpty) {
    return null;
  }
  return (
    page: EditProviderView(provider: provider, path: path),
    onResult: null,
  );
}

RestorablePage? _providerPreview(WidgetRef ref, String rest) {
  final parts = rest.split(':');
  if (parts.length != 2) {
    return null;
  }
  final isRuleSet = parts[0] == '1';
  final path = Uri.decodeComponent(parts[1]);
  return (page: providerPreviewPage(ref, path, isRuleSet), onResult: null);
}

RestorablePage? _moduleEditor(
  BuildContext context,
  WidgetRef ref,
  String rawFileName,
) {
  final fileName = rawFileName == 'new' ? null : rawFileName;
  final module = fileName == null
      ? null
      : ref
            .read(mitmModulesProvider)
            .value
            ?.firstWhereOrNull((item) => item.fileName == fileName);
  if (fileName != null && module == null) {
    return null;
  }
  return (
    page: mitmModuleEditorPage(context, ref, module: module),
    onResult: null,
  );
}

RestorablePage? _mitmBodyEditor(String rest) {
  final parsed = _mitmBodyTarget(rest);
  if (parsed == null) {
    return null;
  }
  final (id, response) = parsed;
  return (
    page: MitmBodyEditorPage(exchangeId: id, response: response),
    onResult: null,
  );
}

RestorablePage? _mitmBodyHex(String rest) {
  final parsed = _mitmBodyTarget(rest);
  if (parsed == null) {
    return null;
  }
  final (id, response) = parsed;
  return (
    page: MitmBodyHexPage(exchangeId: id, response: response),
    onResult: null,
  );
}

(int, bool)? _mitmBodyTarget(String rest) {
  final parts = rest.split(':');
  if (parts.length != 2) {
    return null;
  }
  final id = int.tryParse(parts[0]);
  if (id == null || (parts[1] != '0' && parts[1] != '1')) {
    return null;
  }
  return (id, parts[1] == '1');
}

RestorablePage? _clashProviderEditor(
  BuildContext context,
  WidgetRef ref,
  String rawId,
) {
  final id = rawId == 'new' ? null : int.tryParse(rawId);
  if (rawId != 'new' && id == null) {
    return null;
  }
  if (id != null && clashProviderOf(ref, id) == null) {
    return null;
  }
  return (page: clashProviderEditorPage(context, ref, id: id), onResult: null);
}

RestorablePage? _clashProviderPreview(WidgetRef ref, String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  final page = clashProviderPreviewPage(ref, id);
  if (page == null) {
    return null;
  }
  return (page: page, onResult: null);
}

RestorablePage? _scriptEditor(
  BuildContext context,
  WidgetRef ref,
  String rawId,
) {
  final id = rawId == 'new' ? null : int.tryParse(rawId);
  if (rawId != 'new' && id == null) {
    return null;
  }
  if (id != null && scriptOf(ref, id) == null) {
    return null;
  }
  return (page: scriptEditorPage(context, ref, id: id), onResult: null);
}

RestorablePage? _profileFileEditor(
  BuildContext context,
  WidgetRef ref,
  String rawId,
) {
  final id = int.tryParse(rawId);
  final profile = id == null ? null : ref.read(profileProvider(id));
  if (profile == null) {
    return null;
  }
  return (
    page: profileFileEditorPage(context, ref, profile),
    onResult: (result) {
      if (result is! Uint8List) {
        return;
      }
      stagedProfileFileEdits.value = {
        ...stagedProfileFileEdits.value,
        profile.id: result,
      };
    },
  );
}

RestorablePage? _overrideListEdit(WidgetRef ref, String rest) {
  final parts = rest.split(':');
  if (parts.length < 3) {
    return null;
  }
  final (family, target, keyName) = switch (parts) {
    [final family, 'patch', final keyName] => (family, null, keyName),
    [final family, 'profile', final rawId, final keyName] => (
      family,
      int.tryParse(rawId),
      keyName,
    ),
    _ => (null, null, null),
  };
  if (family == null ||
      keyName == null ||
      (parts[1] == 'profile' && target == null)) {
    return null;
  }
  return switch (family) {
    'dns' => dnsListEditPage(ref, keyName, profileId: target),
    'sniffer' => snifferListEditPage(ref, keyName, profileId: target),
    'tun' => tunListEditPage(ref, keyName, profileId: target),
    _ => null,
  };
}

RestorablePage? _networkListEdit(WidgetRef ref, String key) {
  return networkListEditPage(ref, key);
}
