import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const proxyGridSpacing = 8.0;

/// The inset between a group header's outer shape and its inner card.
const groupHeaderButtonInset = 4.0;

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 +
      measure.textHeight(AppTextStyle.callout) +
      2 +
      measure.textHeight(AppTextStyle.caption1) +
      2;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 +
      measure.textHeight(AppTextStyle.subheadline) * 2 +
      measure.textHeight(AppTextStyle.footnote) +
      8 +
      4;
  return switch (proxyCardType) {
    ProxyCardType.loose =>
      baseHeight + measure.textHeight(AppTextStyle.caption2) + 6,
    ProxyCardType.standard => baseHeight,
    ProxyCardType.compact =>
      baseHeight - measure.textHeight(AppTextStyle.subheadline),
  };
}

double getRowExtent(ProxyCardType proxyCardType) =>
    getItemHeight(proxyCardType) + proxyGridSpacing;

List<BoxShadow> floatingShadows(ColorScheme colorScheme, double lift) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.08 * strength * lift),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.04 * strength * lift),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
}

class GroupOffsets {
  const GroupOffsets(this.groups, this.offsets);

  static const empty = GroupOffsets(<Group>[], <double>[]);

  final List<Group> groups;
  final List<double> offsets;

  bool get isEmpty => offsets.isEmpty;

  double offsetOf(String groupName) {
    final index = groups.indexWhere((group) => group.name == groupName);
    if (index < 0 || index >= offsets.length) {
      return 0;
    }
    return offsets[index];
  }
}

double? selectedRowOffset({
  required List<Proxy> proxies,
  required String? selectedProxyName,
  required int columns,
  required double rowExtent,
}) {
  final index = proxies.indexWhere((proxy) => proxy.name == selectedProxyName);
  if (index < 0) {
    return null;
  }
  return (index ~/ columns) * rowExtent;
}

/// The in-group search control zashboard puts after the type line: a
/// magnifier that opens a field filtering the group's nodes, shown only
/// while the group is open. Typing filters live with the page search's
/// matcher; the clear button empties the keyword and closes the field,
/// and so does tapping away with nothing typed.
class GroupSearchControl extends StatefulWidget {
  const GroupSearchControl({
    super.key,
    required this.keyword,
    required this.open,
    required this.onKeyword,
    required this.onOpen,
  });

  final String keyword;
  final bool open;
  final ValueChanged<String> onKeyword;
  final ValueChanged<bool> onOpen;

  @override
  State<GroupSearchControl> createState() => _GroupSearchControlState();
}

class _GroupSearchControlState extends State<GroupSearchControl> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.keyword,
  );
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant GroupSearchControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.keyword != _controller.text) {
      _controller.text = widget.keyword;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _close() {
    widget.onKeyword('');
    widget.onOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    if (!widget.open) {
      return HoverTooltip(
        message: appLocalizations.search,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpen(true),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: GlyphIcon(
              AppGlyphs.search,
              size: 14,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 128,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            style: AppTextStyle.caption1.of(context),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration.collapsed(
              hintText: appLocalizations.search,
            ),
            onChanged: widget.onKeyword,
            onSubmitted: (_) => _focusNode.unfocus(),
            onTapOutside: (_) {
              if (_controller.text.isEmpty) {
                _close();
              } else {
                _focusNode.unfocus();
              }
            },
          ),
        ),
        HoverTooltip(
          message: appLocalizations.clearSearch,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: GlyphIcon(
                Glyphs.clearField,
                size: 14,
                fill: 1,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void animateScrollTo(ScrollController controller, double offset) {
  if (!controller.hasClients) {
    return;
  }
  final position = controller.position;
  controller.animateTo(
    offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOutCubic,
  );
}
