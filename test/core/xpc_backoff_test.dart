import 'package:fl_clash/core/xpc_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XpcEmptyBackoff', () {
    late XpcEmptyBackoff backoff;
    late DateTime now;

    setUp(() {
      backoff = XpcEmptyBackoff();
      now = DateTime(2026, 11, 14);
      backoff.clock = () => now;
    });

    test('is not backed off before any empty response', () {
      expect(backoff.isBackedOff, isFalse);
    });

    test('backs off for 30 seconds after an empty response', () {
      backoff.noteEmptyResponse();
      expect(backoff.isBackedOff, isTrue);

      now = now.add(const Duration(seconds: 29));
      expect(backoff.isBackedOff, isTrue);

      now = now.add(const Duration(seconds: 1));
      expect(backoff.isBackedOff, isFalse);
    });

    test('a second empty response restarts the 30 second window', () {
      backoff.noteEmptyResponse();
      now = now.add(const Duration(seconds: 25));
      backoff.noteEmptyResponse();

      now = now.add(const Duration(seconds: 29));
      expect(backoff.isBackedOff, isTrue);

      now = now.add(const Duration(seconds: 1));
      expect(backoff.isBackedOff, isFalse);
    });

    test('a success clears the backoff at once', () {
      backoff.noteEmptyResponse();
      expect(backoff.isBackedOff, isTrue);

      backoff.noteSuccess();
      expect(backoff.isBackedOff, isFalse);
    });

    test('a success while not backed off stays not backed off', () {
      backoff.noteSuccess();
      expect(backoff.isBackedOff, isFalse);
    });

    test('each backoff is independent of the others', () {
      final other = XpcEmptyBackoff()..clock = () => now;
      backoff.noteEmptyResponse();

      expect(backoff.isBackedOff, isTrue);
      expect(other.isBackedOff, isFalse);
    });
  });
}
