import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/mitm_body.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/mitm.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _imageMaxHeight = 240.0;
const _hexMaxPerLine = 16;
const _hexPerLineStep = 4;
const _hexPadding = 16.0;
const _hexLineGap = 4.0;

class MitmBodySection extends StatelessWidget {
  final String title;
  final MitmBodyContent content;
  final int exchangeId;
  final bool response;

  const MitmBodySection({
    super.key,
    required this.title,
    required this.content,
    required this.exchangeId,
    required this.response,
  });

  void _open(BuildContext context) {
    unawaited(
      pushRestorable(
        context,
        EditorPage(
          title: title,
          content: content.text,
          language: content.language,
        ),
        'mitmBodyEditor:$exchangeId:${response ? 1 : 0}',
      ),
    );
  }

  String? _footer(AppLocalizations appLocalizations) {
    final lines = [
      if (content.encoding.isNotEmpty)
        appLocalizations.httpBodyUndecoded(content.encoding)
      else if (content.truncated)
        appLocalizations.httpBodyTruncated,
      if (content.format == MitmBodyFormat.protobuf)
        appLocalizations.httpBodyProtobufGuess,
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    if (content.bytes.isEmpty) {
      return generateSection(
        title: title,
        items: [ListItem(title: Text(appLocalizations.httpBodyNotKept))],
      );
    }
    final size = Text(
      content.bytes.length.traffic.show,
      style: AppTextStyle.subheadline
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    );
    final hex = _MitmHexView(title: title, content: content);
    return generateSection(
      title: title,
      footer: _footer(appLocalizations),
      items: switch (content.kind) {
        MitmBodyKind.text => [
          DecorationListItem(
            onPressed: () => _open(context),
            title: Text(
              content.preview,
              style: AppTextStyle.footnote.of(context).toJetBrainsMono,
            ),
          ),
          if (content.isCut)
            ListItem(
              title: Text(appLocalizations.viewAll),
              onTap: () => _open(context),
            ),
          ListItem.open(
            title: Text(appLocalizations.hex),
            trailing: size,
            widget: hex,
            restorationId: 'mitmBodyHex:$exchangeId:${response ? 1 : 0}',
          ),
        ],
        MitmBodyKind.image => [
          DecorationListItem(
            title: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _imageMaxHeight),
                child: Image.memory(
                  content.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, _, _) =>
                      Text(appLocalizations.binaryData),
                ),
              ),
            ),
          ),
          ListItem.open(
            title: Text(appLocalizations.hex),
            trailing: size,
            widget: hex,
            restorationId: 'mitmBodyHex:$exchangeId:${response ? 1 : 0}',
          ),
        ],
        MitmBodyKind.binary => [
          ListItem.open(
            title: Text(appLocalizations.binaryData),
            trailing: size,
            widget: hex,
            restorationId: 'mitmBodyHex:$exchangeId:${response ? 1 : 0}',
          ),
        ],
      },
    );
  }
}

/// Every byte of a body. Lines are formatted as they scroll in, at as many
/// bytes a line, in fours, as the width holds.
class _MitmHexView extends StatelessWidget {
  final String title;
  final MitmBodyContent content;

  const _MitmHexView({required this.title, required this.content});

  Future<void> _copyBase64(BuildContext context) async {
    final text = await compute(base64Encode, content.bytes);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    dialogs.showBanner(context.appLocalizations.copySuccess);
  }

  int _perLine(double width, double charWidth) {
    final length = content.bytes.length;
    var perLine = _hexMaxPerLine;
    while (perLine > _hexPerLineStep &&
        mitmHexLineLength(length, perLine) * charWidth > width) {
      perLine -= _hexPerLineStep;
    }
    return perLine;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final style = AppTextStyle.footnote.of(context).toJetBrainsMono;
    return Scaffold(
      title: title,
      menuItems: [
        PopupMenuItem(
          glyph: AppGlyphs.copy,
          label: appLocalizations.copyAsBase64,
          onPressed: () => _copyBase64(context),
        ),
      ],
      body: WidthBuilder(
        builder: (context, width) {
          final painter = TextPainter(
            text: TextSpan(text: '0', style: style),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final charWidth = painter.width;
          final lineHeight = painter.height;
          painter.dispose();
          final bytes = content.bytes;
          final perLine = _perLine(width - _hexPadding * 2, charWidth);
          return ArrivalCacheExtentBuilder(
            builder: (cacheExtent) => CustomScrollView(
              scrollCacheExtent: cacheExtent,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: _hexPadding)
                      .copyWith(
                        top: context.contentTopPadding,
                        bottom: 16 + context.bottomInset,
                      ),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      if (content.truncated)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              appLocalizations.httpBodyTruncated,
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      SliverPrismList(
                        itemCount: (bytes.length + perLine - 1) ~/ perLine,
                        itemExtent: lineHeight + _hexLineGap,
                        addRepaintBoundaries: false,
                        itemBuilder: (_, index) => Text(
                          mitmHexLine(bytes, index * perLine, perLine),
                          style: style,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rebuilds a captured body page for navigation restore. The body is
/// refetched from the Core; a body the Core has already evicted shows empty.
class MitmBodyEditorPage extends ConsumerWidget {
  const MitmBodyEditorPage({
    super.key,
    required this.exchangeId,
    required this.response,
  });

  final int exchangeId;
  final bool response;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = _bodyContent(context, ref);
    if (content == null) {
      return _MitmBodyLoading(title: _bodyTitle(context));
    }
    return EditorPage(
      title: _bodyTitle(context),
      content: content.text,
      language: content.language,
    );
  }

  String _bodyTitle(BuildContext context) => response
      ? context.appLocalizations.responseBody
      : context.appLocalizations.requestBody;

  MitmBodyContent? _bodyContent(BuildContext context, WidgetRef ref) {
    final exchange = ref.watch(mitmExchangeProvider(exchangeId)).value;
    if (exchange == null) {
      return null;
    }
    final header = response ? exchange.responseHeader : exchange.requestHeader;
    return ref
        .watch(
          mitmBodyProvider(
            exchangeId,
            response: response,
            contentType: mitmHeaderValue(header, 'Content-Type'),
          ),
        )
        .value;
  }
}

/// Rebuilds a captured body hex page for navigation restore.
class MitmBodyHexPage extends ConsumerWidget {
  const MitmBodyHexPage({
    super.key,
    required this.exchangeId,
    required this.response,
  });

  final int exchangeId;
  final bool response;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exchange = ref.watch(mitmExchangeProvider(exchangeId)).value;
    if (exchange == null) {
      return _MitmBodyLoading(title: _bodyTitle(context));
    }
    final header = response ? exchange.responseHeader : exchange.requestHeader;
    final content = ref
        .watch(
          mitmBodyProvider(
            exchangeId,
            response: response,
            contentType: mitmHeaderValue(header, 'Content-Type'),
          ),
        )
        .value;
    if (content == null) {
      return _MitmBodyLoading(title: _bodyTitle(context));
    }
    return _MitmHexView(title: _bodyTitle(context), content: content);
  }

  String _bodyTitle(BuildContext context) => response
      ? context.appLocalizations.responseBody
      : context.appLocalizations.requestBody;
}

class _MitmBodyLoading extends StatelessWidget {
  const _MitmBodyLoading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: title,
      body: const Center(child: ActivityIndicator()),
    );
  }
}
