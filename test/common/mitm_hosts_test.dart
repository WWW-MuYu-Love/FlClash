import 'package:fl_clash/providers/mitm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeMitmHost lowercases and strips a port', () {
    expect(normalizeMitmHost('movies.muyu.love'), 'movies.muyu.love');
    expect(normalizeMitmHost('Movies.MuYu.Love'), 'movies.muyu.love');
    expect(normalizeMitmHost('movies.muyu.love:443'), 'movies.muyu.love');
    expect(normalizeMitmHost('  cdn.muyu.love  '), 'cdn.muyu.love');
    expect(normalizeMitmHost(''), '');
  });
}
