import 'package:fl_clash/ui/icons/icons.dart';

typedef BrandIcon = ({String? asset, Glyph? glyph});

const _assetPrefix = 'assets/images/services';

const Map<String, BrandIcon> _brandIcons = {
  'apple': (asset: '$_assetPrefix/apple.svg', glyph: null),
  'appletv': (asset: '$_assetPrefix/appletv.svg', glyph: null),
  'bilibili': (asset: '$_assetPrefix/bilibili.svg', glyph: null),
  'chatgpt': (asset: '$_assetPrefix/openai.svg', glyph: null),
  'claude': (asset: '$_assetPrefix/claude.svg', glyph: null),
  'discord': (asset: '$_assetPrefix/discord.svg', glyph: null),
  'disney': (asset: '$_assetPrefix/disneyplus.svg', glyph: null),
  'disneyplus': (asset: '$_assetPrefix/disneyplus.svg', glyph: null),
  'gemini': (asset: '$_assetPrefix/gemini.svg', glyph: null),
  'github': (asset: '$_assetPrefix/github.svg', glyph: null),
  'google': (asset: '$_assetPrefix/google.svg', glyph: null),
  'netflix': (asset: '$_assetPrefix/netflix.svg', glyph: null),
  'openai': (asset: '$_assetPrefix/openai.svg', glyph: null),
  'prime': (asset: '$_assetPrefix/primevideo.svg', glyph: null),
  'primevideo': (asset: '$_assetPrefix/primevideo.svg', glyph: null),
  'spotify': (asset: '$_assetPrefix/spotify.svg', glyph: null),
  'steam': (asset: '$_assetPrefix/steam.svg', glyph: null),
  'tiktok': (asset: '$_assetPrefix/tiktok.svg', glyph: null),
  'youtube': (asset: '$_assetPrefix/youtube.svg', glyph: null),
  'rocket': (asset: null, glyph: AppGlyphs.send),
};

final _nonAlphanumeric = RegExp('[^a-z0-9]');

String _compactBrandName(String value) =>
    value.toLowerCase().replaceAll(_nonAlphanumeric, '');

/// The built-in mark for [groupName], or null when no brand matches.
/// Microsoft and OneDrive are absent: Simple Icons 13.0.0 carries neither.
BrandIcon? brandIconFor(String groupName) {
  final key = _compactBrandName(groupName);
  if (key.isEmpty) {
    return null;
  }
  return _brandIcons[key];
}
