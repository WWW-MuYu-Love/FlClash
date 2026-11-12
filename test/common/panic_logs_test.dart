import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('panic logs read oldest first and skip missing files', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    expect(await readPanicLogs(dir.path), isEmpty);

    await File('${dir.path}/panic.log').writeAsString('panic: new\n');
    expect(await readPanicLogs(dir.path), contains('panic: new'));

    await File('${dir.path}/panic.log.old').writeAsString('panic: old\n');
    final combined = await readPanicLogs(dir.path);
    expect(
      combined.indexOf('panic: old'),
      lessThan(combined.indexOf('panic: new')),
    );
    expect(combined, contains('--- panic.log.old ---'));
    expect(combined, contains('--- panic.log ---'));
  });
}
