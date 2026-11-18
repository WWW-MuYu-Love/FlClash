import 'package:fl_clash/common/brand_icons.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:test/test.dart';

void main() {
  group('brandIconFor', () {
    test('matches bundled service assets by group name', () {
      expect(
        brandIconFor('YouTube')?.asset,
        'assets/images/services/youtube.svg',
      );
      expect(
        brandIconFor('Google')?.asset,
        'assets/images/services/google.svg',
      );
      expect(
        brandIconFor('GitHub')?.asset,
        'assets/images/services/github.svg',
      );
      expect(
        brandIconFor('Netflix')?.asset,
        'assets/images/services/netflix.svg',
      );
      expect(
        brandIconFor('Spotify')?.asset,
        'assets/images/services/spotify.svg',
      );
      expect(brandIconFor('Steam')?.asset, 'assets/images/services/steam.svg');
      expect(brandIconFor('Apple')?.asset, 'assets/images/services/apple.svg');
      expect(
        brandIconFor('Apple TV')?.asset,
        'assets/images/services/appletv.svg',
      );
    });

    test('ignores case, spaces and punctuation in the name', () {
      expect(
        brandIconFor('  YOUTUBE! ')?.asset,
        'assets/images/services/youtube.svg',
      );
      expect(
        brandIconFor('apple-tv')?.asset,
        'assets/images/services/appletv.svg',
      );
    });

    test('maps common aliases to the same asset', () {
      expect(
        brandIconFor('ChatGPT')?.asset,
        'assets/images/services/openai.svg',
      );
      expect(
        brandIconFor('Disney')?.asset,
        'assets/images/services/disneyplus.svg',
      );
      expect(
        brandIconFor('Prime')?.asset,
        'assets/images/services/primevideo.svg',
      );
    });

    test('maps a rocket to the send glyph, not an asset', () {
      final brand = brandIconFor('Rocket');
      expect(brand?.asset, isNull);
      expect(brand?.glyph, AppGlyphs.send);
    });

    test('returns null for unknown names and for names with no letters', () {
      expect(brandIconFor('My Nodes'), isNull);
      expect(brandIconFor('🚀 节点选择'), isNull);
      expect(brandIconFor(''), isNull);
    });

    test('does not match a brand merely contained in the name', () {
      expect(brandIconFor('Pineapple'), isNull);
      expect(brandIconFor('YouTube 4K'), isNull);
    });

    test('has no entry for brands Simple Icons 13.0.0 does not carry', () {
      expect(brandIconFor('Microsoft'), isNull);
      expect(brandIconFor('OneDrive'), isNull);
    });
  });
}
