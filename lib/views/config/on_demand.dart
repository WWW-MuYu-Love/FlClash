import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

class OnDemandView extends ConsumerStatefulWidget {
  const OnDemandView({super.key, this.isAndroid, this.isMacOS, this.isWindows});

  final bool? isAndroid;
  final bool? isMacOS;
  final bool? isWindows;

  @override
  ConsumerState createState() => _OnDemandViewState();
}

class _OnDemandViewState extends ConsumerState<OnDemandView>
    with UniqueKeyStateMixin {
  static const _authorizeButtonPadding = 12.0;
  static const _minAuthorizeButtonWidth = 80.0;

  bool get _isAndroid => widget.isAndroid ?? system.isAndroid;

  bool get _isMacOS => widget.isMacOS ?? system.isMacOS;

  bool get _isWindows => widget.isWindows ?? system.isWindows;

  bool get _needsLocationPermission => _isAndroid || _isMacOS || _isWindows;

  void _handlePermanentlyDeniedLocationPermission() {
    if (_isMacOS) {
      final appLocalizations = context.appLocalizations;
      dialogs.showAlert(
        title: appLocalizations.locationPermissionRequired,
        message: TextSpan(
          style: AppTextStyle.subheadline.of(context),
          text: appLocalizations.locationPermissionGuide(appName),
        ),
      );
    } else if (_isAndroid) {
      app?.openAppSettings();
    } else if (_isWindows) {
      unawaited(_promptLocationSettings());
    }
  }

  Future<void> _promptLocationSettings() async {
    final appLocalizations = context.appLocalizations;
    final needGo = await dialogs.showMessage(
      title: appLocalizations.locationPermissionRequired,
      message: TextSpan(text: appLocalizations.locationPermissionDeniedMessage),
      confirmText: appLocalizations.go,
    );
    if (needGo != true) {
      return;
    }
    if (_isWindows) {
      unawaited(launchUrl(Uri.parse('ms-settings:privacy-location')));
    } else {
      unawaited(app?.openAppSettings());
    }
  }

  Future<void> _handleRequestLocationPermission() async {
    final permission = ref.read(locationPermissionsProvider);
    if (permission == WifiSsidPermission.granted) {
      return;
    }
    if (permission == WifiSsidPermission.permanentlyDenied) {
      _handlePermanentlyDeniedLocationPermission();
      return;
    }
    final WifiSsidPermission? res;
    try {
      res = await ref.read(locationPermissionsProvider.notifier).request();
    } on PlatformException catch (e) {
      commonPrint.log('requestPermission error $e', logLevel: LogLevel.warning);
      return;
    }
    if (res == null || !mounted) {
      return;
    }
    switch (res) {
      case WifiSsidPermission.granted:
        return;
      case WifiSsidPermission.permanentlyDenied:
        _handlePermanentlyDeniedLocationPermission();
        return;
      case WifiSsidPermission.denied:
        await _promptLocationSettings();
    }
  }

  void _handleRequestIgnoreBatteryOptimization() {
    if (ref.read(batteryOptimizationIgnoredProvider).value == true) {
      return;
    }
    unawaited(ref.read(batteryOptimizationIgnoredProvider.notifier).request());
  }

  Future<void> _handleAddOrUpdate([String? ssid]) async {
    final ssids = ref.read(excludeSSIDsProvider);
    final appLocalizations = context.appLocalizations;
    final newSSID = await dialogs.showCommonDialog<String>(
      child: InputDialog(
        title: ssid == null
            ? appLocalizations.addSsid
            : appLocalizations.editSsid,
        value: ssid ?? '',
        maxLength: 32,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return appLocalizations.emptyTip('SSID').trim();
          }
          if (ssids.contains(value) && ssid != value) {
            return appLocalizations.existsTip('SSID').trim();
          }
          return null;
        },
      ),
    );
    if (newSSID == null || ssid == newSSID) {
      return;
    }
    ref.read(excludeSSIDsProvider.notifier).update((state) {
      final newSSIDS = state.toSet();
      if (ssid != null) {
        newSSIDS.remove(ssid);
      }
      return [...newSSIDS, newSSID];
    });
    // Renaming keeps the SSID's action.
    if (ssid != null) {
      ref.read(directSSIDsProvider.notifier).update((state) {
        if (!state.contains(ssid)) {
          return state;
        }
        return [...state.where((item) => item != ssid), newSSID];
      });
    }
  }

  void _setSsidAction(String ssid, bool direct) {
    ref.read(directSSIDsProvider.notifier).update((state) {
      final next = state.toSet();
      if (direct) {
        next.add(ssid);
      } else {
        next.remove(ssid);
      }
      return next.toList();
    });
  }

  void _handleReorder(int oldIndex, newIndex) {
    ref.read(excludeSSIDsProvider.notifier).update((value) {
      return value.copyAndReorder(oldIndex, newIndex);
    });
  }

  Widget _buildItem({
    required String ssid,
    required int index,
    required int length,
    required bool isSelected,
    required bool isEditing,
    required bool isDirect,
  }) {
    final position = ItemPosition.get(index, length);
    final appLocalizations = context.appLocalizations;
    return ReorderDragStartListener(
      key: ValueKey(ssid),
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _SsidSwipeCard(
          onSetAction: (direct) => _setSsidAction(ssid, direct),
          child: ItemPositionProvider(
            position: position,
            child: SelectedDecorationListItem(
              isEditing: isEditing,
              title: TooltipText(
                text: Text(ssid, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              subtitle: Text(
                isDirect
                    ? appLocalizations.direct
                    : appLocalizations.disconnect,
              ),
              isSelected: isSelected,
              onSelected: () {
                ref.read(itemsProvider(key).notifier).update((state) {
                  final newState = Set<String>.from(state)..addOrRemove(ssid);
                  return newState;
                });
              },
              onPressed: () {
                _handleAddOrUpdate(ssid);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _handleSelectAll() {
    final excludeSSIDs = ref.read(excludeSSIDsProvider).toSet();
    ref.read(itemsProvider(key).notifier).update((selected) {
      return selected.containsAll(excludeSSIDs) ? {} : excludeSSIDs;
    });
  }

  void _handleDelete() {
    final selectedItems = ref.read(itemsProvider(key));
    ref.read(excludeSSIDsProvider.notifier).update((excludeSSIDs) {
      return excludeSSIDs
          .where((item) => !selectedItems.contains(item))
          .toList();
    });
    ref.read(directSSIDsProvider.notifier).update((directSSIDs) {
      return directSSIDs
          .where((item) => !selectedItems.contains(item))
          .toList();
    });
    ref.read(itemsProvider(key).notifier).value = {};
  }

  Widget _buildAuthorizeButton({
    required bool authorized,
    required VoidCallback onPressed,
  }) {
    final appLocalizations = context.appLocalizations;
    return MinFilledButtonTheme(
      child: ElasticButton(
        child: FilledButton(
          style: ButtonStyle.from(
            backgroundColor: authorized
                ? null
                : context.colorScheme.errorContainer,
            foregroundColor: authorized
                ? null
                : context.colorScheme.onErrorContainer,
            padding: const EdgeInsets.symmetric(
              horizontal: _authorizeButtonPadding,
            ),
            minimumSize: const Size(_minAuthorizeButtonWidth, 40),
          ),
          onPressed: onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0,
                  child: Text(
                    authorized
                        ? appLocalizations.tapToAuthorize
                        : appLocalizations.authorized,
                  ),
                ),
              ),
              Text(
                authorized
                    ? appLocalizations.authorized
                    : appLocalizations.tapToAuthorize,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrerequisiteItem({
    required String title,
    required Widget action,
  }) {
    return DecorationListItem(title: TooltipLabel(title), trailing: action);
  }

  Widget _buildBatteryOptimizationItem() {
    final appLocalizations = context.appLocalizations;
    final ignored = ref.watch(batteryOptimizationIgnoredProvider);
    final isLoading = ignored.isLoading;
    return _buildPrerequisiteItem(
      title: appLocalizations.ignoreBatteryOptimization,
      action: Stack(
        alignment: Alignment.centerRight,
        children: [
          Visibility(
            visible: !isLoading,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _buildAuthorizeButton(
              authorized: ignored.value ?? false,
              onPressed: _handleRequestIgnoreBatteryOptimization,
            ),
          ),
          if (isLoading) const ActivityIndicator(size: 24),
        ],
      ),
    );
  }

  Widget _buildLocationPermissionItem() {
    final appLocalizations = context.appLocalizations;
    final granted = ref.watch(
      locationPermissionsProvider.select(
        (state) => state == WifiSsidPermission.granted,
      ),
    );
    return _buildPrerequisiteItem(
      title: appLocalizations.locationPermission,
      action: _buildAuthorizeButton(
        authorized: granted,
        onPressed: _handleRequestLocationPermission,
      ),
    );
  }

  Widget _buildPrerequisites() {
    final appLocalizations = context.appLocalizations;
    return generateSection(
      title: appLocalizations.prerequisites,
      items: [
        if (_isAndroid) _buildBatteryOptimizationItem(),
        if (_needsLocationPermission) _buildLocationPermissionItem(),
      ],
      footer: _needsLocationPermission
          ? appLocalizations.locationPermissionDesc
          : null,
    );
  }

  Widget _buildExcludeSsidsHeader() {
    final appLocalizations = context.appLocalizations;
    final hasSelection = ref.watch(itemsProvider(key)).isNotEmpty;
    return ListHeader(
      title: appLocalizations.excludeSsids,
      actions: [
        if (hasSelection) ...[
          IconButtonData(
            glyph: AppGlyphs.delete,
            tooltip: appLocalizations.delete,
            onPressed: _handleDelete,
          ),
          IconButtonData(
            glyph: AppGlyphs.selectAll,
            tooltip: appLocalizations.selectAll,
            onPressed: _handleSelectAll,
          ),
        ] else
          IconButtonData(
            glyph: AppGlyphs.addCircle,
            tooltip: appLocalizations.add,
            onPressed: _handleAddOrUpdate,
          ),
      ],
    );
  }

  Widget _buildExcludeSsidsList(
    List<String> excludeSSIDs,
    Set<dynamic> selectedItems,
    Set<String> directSSIDs,
  ) {
    if (excludeSSIDs.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 12),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 48),
            child: NullStatus(
              label: context.appLocalizations.ssidsEmpty,
              illustration: NullStatusIllustration.wifi,
            ),
          ),
        ),
      );
    }
    Widget itemAt(int index) => _buildItem(
      isEditing: selectedItems.isNotEmpty,
      ssid: excludeSSIDs[index],
      index: index,
      isSelected: selectedItems.contains(excludeSSIDs[index]),
      length: excludeSSIDs.length,
      isDirect: directSSIDs.contains(excludeSSIDs[index]),
    );
    return SliverPadding(
      padding: const EdgeInsets.only(top: 12),
      sliver: SliverPrismReorderableList(
        itemBuilder: (_, index) => itemAt(index),
        proxyDecorator: (child, index, animation) =>
            commonProxyDecorator(itemAt(index), index, animation),
        itemCount: excludeSSIDs.length,
        onReorderItem: _handleReorder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final excludeSSIDs = ref.watch(excludeSSIDsProvider);
    final directSSIDs = ref.watch(directSSIDsProvider).toSet();
    final selectedItems = ref.watch(itemsProvider(key));
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ).copyWith(top: context.sectionsTopPadding),
            sliver: SliverToBoxAdapter(child: _buildPrerequisites()),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: _buildExcludeSsidsHeader()),
          ),
          _buildExcludeSsidsList(excludeSSIDs, selectedItems, directSSIDs),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ).copyWith(bottom: 16 + context.bottomInset),
            sliver: SliverToBoxAdapter(
              child: ListFooter(
                text: context.appLocalizations.excludeSsidsDesc,
              ),
            ),
          ),
        ],
      ),
      title: context.appLocalizations.onDemand,
    );
  }
}

/// A card that swipes sideways to reveal round action buttons, like the
/// app cards on LiveContainer's app page. Swiping past half the card runs
/// the action; a shorter swipe leaves the button open to tap.
class _SsidSwipeCard extends StatefulWidget {
  const _SsidSwipeCard({required this.onSetAction, required this.child});

  final ValueChanged<bool> onSetAction;
  final Widget child;

  @override
  State<_SsidSwipeCard> createState() => _SsidSwipeCardState();
}

class _SsidSwipeCardState extends State<_SsidSwipeCard>
    with SingleTickerProviderStateMixin {
  // Wide enough for the longest action label ("Disconnect") on one line;
  // a wrapped label makes the button column taller than the card.
  static const _revealWidth = 88.0;
  static const _buttonWidth = 84.0;

  late final AnimationController _controller;
  Animation<double>? _offsetAnimation;
  double _offset = 0;
  bool _isOpen = false;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 250),
        )..addListener(() {
          setState(() {
            _offset = _offsetAnimation?.value ?? _offset;
          });
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _isOpen = target != 0;
    _offsetAnimation = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }

  void _execute(bool direct) {
    widget.onSetAction(direct);
    _animateTo(0);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _controller.stop();
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_width, _width);
    });
  }

  void _settle() {
    // Snap to the nearest resting position without running an action.
    if (_offset >= _revealWidth / 2) {
      _animateTo(_revealWidth);
    } else if (_offset <= -_revealWidth / 2) {
      _animateTo(-_revealWidth);
    } else {
      _animateTo(0);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_width <= 0) {
      _animateTo(0);
      return;
    }
    final halfWidth = _width * 0.5;
    if (_offset >= halfWidth) {
      _execute(false);
    } else if (_offset <= -halfWidth) {
      _execute(true);
    } else {
      _settle();
    }
  }

  // A drag can be cancelled instead of ended when the list's vertical scroll
  // wins the gesture arena; without this the card is left wherever the drag
  // stopped, with no snap-back.
  void _onDragCancel() {
    _settle();
  }

  // A round swipe button like the one on LiveContainer's app page: a solid
  // circle with a white icon, and the action label beneath it. The circle is
  // 40, not 48: circle + gap + label must fit inside the two-line card
  // (~62), or the label spills below the card.
  Widget _swipeActionButton({
    required String label,
    required Glyph glyph,
    required Color color,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _buttonWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(color: color, shape: AppShape.full),
              child: Center(
                child: GlyphIcon(glyph, size: 20, color: foreground),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _swipeActionButton(
                    label: appLocalizations.disconnect,
                    glyph: AppGlyphs.wifiOff,
                    color: colorScheme.error,
                    foreground: colorScheme.onError,
                    onTap: () => _execute(false),
                  ),
                  _swipeActionButton(
                    label: appLocalizations.direct,
                    glyph: AppGlyphs.link,
                    color: colorScheme.primary,
                    foreground: colorScheme.onPrimary,
                    onTap: () => _execute(true),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: Offset(_offset, 0),
              child: GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                onTap: _isOpen ? () => _animateTo(0) : null,
                child: IgnorePointer(ignoring: _isOpen, child: widget.child),
              ),
            ),
          ],
        );
      },
    );
  }
}
