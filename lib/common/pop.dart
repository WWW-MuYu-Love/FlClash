import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Pops the route under [context], waiting out a drag back still settling.
///
/// A pop started while a cancelled drag back is springing the page back to
/// rest is killed by the drag-back follower, which keeps driving the route's
/// controller back to rest and stops the pop-out animation, stranding the
/// route: popped from the history, but its animation sits at completed, so
/// the page stays painted and later pops do nothing. When no drag back is
/// in progress, this pops immediately, exactly like [Navigator.pop].
void popAfterDragBack(BuildContext context, [Object? result]) {
  _popAfterDragBack(context, () => Navigator.of(context).pop(result));
}

/// The [Navigator.maybePop] counterpart of [popAfterDragBack].
void maybePopAfterDragBack(BuildContext context, [Object? result]) {
  _popAfterDragBack(
    context,
    () => unawaited(Navigator.maybePop(context, result)),
  );
}

/// The [BuildContextExtension.safeNestedPop] counterpart of
/// [popAfterDragBack]: pops the sheet's nested navigator when the context
/// sits inside one, else the enclosing navigator.
void safeNestedPopAfterDragBack(BuildContext context, [Object? result]) {
  _popAfterDragBack(context, () => context.safeNestedPop(result));
}

/// The [NavigatorState.maybePop] counterpart of [maybePopAfterDragBack],
/// for callers that hold a [NavigatorState] but no [BuildContext].
void maybePopStateAfterDragBack(NavigatorState navigator) {
  if (!navigator.userGestureInProgress) {
    unawaited(navigator.maybePop());
    return;
  }
  final notifier = navigator.userGestureInProgressNotifier;
  late final VoidCallback listener;
  listener = () {
    if (notifier.value) {
      return;
    }
    notifier.removeListener(listener);
    if (navigator.mounted) {
      unawaited(navigator.maybePop());
    }
  };
  notifier.addListener(listener);
}

/// Intercepts the system back button (Android) while a drag back is
/// settling, the same hazard [popAfterDragBack] waits out. Register it
/// before the app's own back handling so it runs first; returning true
/// consumes the press and the pop is deferred until the gesture ends.
class DragBackPopRouteObserver extends WidgetsBindingObserver {
  DragBackPopRouteObserver(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<bool> didPopRoute() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null || !navigator.userGestureInProgress) {
      return false;
    }
    maybePopStateAfterDragBack(navigator);
    return true;
  }
}

void _popAfterDragBack(BuildContext context, VoidCallback pop) {
  final navigator = Navigator.of(context);
  if (!navigator.userGestureInProgress) {
    pop();
    return;
  }
  final route = ModalRoute.of(context);
  final notifier = navigator.userGestureInProgressNotifier;
  late final VoidCallback listener;
  listener = () {
    if (notifier.value) {
      return;
    }
    notifier.removeListener(listener);
    if (!context.mounted || (route != null && !route.isCurrent)) {
      return;
    }
    pop();
  };
  notifier.addListener(listener);
}
