import 'package:flutter/widgets.dart';

/// Hooks the app sets so pages carrying a restoration id are recorded in the
/// navigation path. Kept free of view imports to avoid an import cycle.
class NavigationRestorationHooks {
  static void Function(String descriptor)? onPush;
  static void Function(String descriptor)? onPop;
}

/// A sub-page rebuilt for navigation restore, with the handler for the value
/// it pops with (the same save the opening row's onChanged performs).
typedef RestorablePage = ({Widget page, ValueChanged<dynamic>? onResult});
