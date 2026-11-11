import 'package:fl_clash/common/navigation_hooks.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/config/advanced.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/views/config/mitm_modules.dart';
import 'package:fl_clash/views/config/on_demand.dart';
import 'package:fl_clash/views/profiles/custom/custom.dart';
import 'package:fl_clash/views/profiles/extend/extend.dart';
import 'package:fl_clash/views/profiles/preview.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart';

/// Pushes a restorable sub-page, recording it in the navigation path until
/// it pops.
Future<T?> pushRestorable<T>(
  BuildContext context,
  Widget child,
  String restorationId,
) {
  NavigationRestorationHooks.onPush?.call(restorationId);
  final future = BaseNavigator.push<T>(context, child);
  future.then((_) {
    NavigationRestorationHooks.onPop?.call(restorationId);
  });
  return future;
}

/// Rebuilds a restorable sub-page from its descriptor, or null when the
/// descriptor is unknown or its target no longer exists.
Widget? navigationPathPage(WidgetRef ref, String descriptor) {
  return switch (descriptor) {
    'tools/general' => const GeneralView(),
    'tools/general/onDemand' => const OnDemandView(),
    'tools/advanced' => const AdvancedConfigView(),
    _ when descriptor.startsWith('mitmModule:') => _mitmModule(
      descriptor.substring('mitmModule:'.length),
    ),
    _ when descriptor.startsWith('profileExtend:') => _profileExtend(
      descriptor.substring('profileExtend:'.length),
    ),
    _ when descriptor.startsWith('profileCustom:') => _profileCustom(
      descriptor.substring('profileCustom:'.length),
    ),
    _ when descriptor.startsWith('profilePreview:') => _profilePreview(
      ref,
      descriptor.substring('profilePreview:'.length),
    ),
    _ => null,
  };
}

Widget? _mitmModule(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return MitmModuleView(id: id);
}

Widget? _profileExtend(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return ExtendView(profileId: id);
}

Widget? _profileCustom(String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  return CustomProfileView(profileId: id);
}

Widget? _profilePreview(WidgetRef ref, String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    return null;
  }
  final profiles = ref.read(profilesProvider);
  final profile = profiles.where((element) => element.id == id).firstOrNull;
  if (profile == null) {
    return null;
  }
  return PreviewProfileView(profile: profile);
}
