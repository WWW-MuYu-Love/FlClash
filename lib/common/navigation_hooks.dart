/// Hooks the app sets so pages carrying a restoration id are recorded in the
/// navigation path. Kept free of view imports to avoid an import cycle.
class NavigationRestorationHooks {
  static void Function(String descriptor)? onPush;
  static void Function(String descriptor)? onPop;
}
