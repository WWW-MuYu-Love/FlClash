import 'package:fl_clash/core/method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a call without a route omits it from the wire', () {
    const call = CoreMethodCall(
      id: '1',
      method: CoreMethod.probeServices,
      arguments: {
        'names': ['youtube'],
      },
    );

    expect(call.toJson(), {
      'id': '1',
      'method': 'probe.services',
      'arguments': {
        'names': ['youtube'],
      },
    });
  });

  test('a call pinned to the app core round-trips its route', () {
    const call = CoreMethodCall(
      id: '2',
      method: CoreMethod.probeServices,
      arguments: {
        'names': ['youtube'],
      },
      route: CoreRoute.app,
    );

    final json = call.toJson();
    expect(json['route'], 'app');

    final decoded = CoreMethodCall.fromJson(json);
    expect(decoded.route, CoreRoute.app);
    expect(decoded.method, CoreMethod.probeServices);
  });

  test('an unknown route is ignored', () {
    final decoded = CoreMethodCall.fromJson({
      'id': '3',
      'method': 'probe.services',
      'arguments': null,
      'route': 'sidecar',
    });

    expect(decoded.route, isNull);
  });
}
