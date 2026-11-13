import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/network_error.dart';
import 'package:fl_clash/common/webdav.dart';
import 'package:fl_clash/core/desktop/helper_client.dart';
import 'package:fl_clash/core/desktop/launch_policy.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations appLocalizations;

  setUpAll(() async {
    appLocalizations = await AppLocalizations.load(const Locale('en'));
  });

  DioException dioError(
    DioExceptionType type, {
    int? statusCode,
    Object? cause,
  }) {
    final options = RequestOptions(path: '/');
    return DioException(
      requestOptions: options,
      type: type,
      error: cause,
      response: statusCode == null
          ? null
          : Response<void>(requestOptions: options, statusCode: statusCode),
    );
  }

  group('Dio failures name their cause', () {
    final cases = <String, (DioException, String Function(AppLocalizations))>{
      'timeout': (
        dioError(DioExceptionType.receiveTimeout),
        (l) => l.networkTimeoutError,
      ),
      'host lookup': (
        dioError(
          DioExceptionType.connectionError,
          cause: const SocketException("Failed host lookup: 'sub.example'"),
        ),
        (l) => l.networkHostLookupError,
      ),
      'refused connection': (
        dioError(
          DioExceptionType.connectionError,
          cause: const SocketException('Connection refused'),
        ),
        (l) => l.networkConnectionError,
      ),
      'TLS handshake': (
        dioError(
          DioExceptionType.unknown,
          cause: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        ),
        (l) => l.networkTlsError,
      ),
      'bad certificate': (
        dioError(DioExceptionType.badCertificate),
        (l) => l.networkTlsError,
      ),
      'HTTP 403': (
        dioError(DioExceptionType.badResponse, statusCode: 403),
        (l) => l.networkAccessDeniedError(403),
      ),
      'HTTP 404': (
        dioError(DioExceptionType.badResponse, statusCode: 404),
        (l) => l.networkNotFoundError(404),
      ),
      'HTTP 429': (
        dioError(DioExceptionType.badResponse, statusCode: 429),
        (l) => l.networkRateLimitedError,
      ),
      'HTTP 502': (
        dioError(DioExceptionType.badResponse, statusCode: 502),
        (l) => l.networkServerError(502),
      ),
      'HTTP 400': (
        dioError(DioExceptionType.badResponse, statusCode: 400),
        (l) => l.networkBadResponseError(400),
      ),
    };
    for (final MapEntry(key: name, value: (error, expected)) in cases.entries) {
      test(name, () {
        expect(
          networkErrorMessage(error, appLocalizations),
          expected(appLocalizations),
        );
      });
    }
  });

  test('keeps the detail of an unclassified Dio failure', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/'),
      error: const FormatException('bad body'),
      message: 'bad body',
    );
    expect(
      networkErrorMessage(error, appLocalizations),
      appLocalizations.networkRequestFailed('bad body'),
    );
  });

  test('leaves bare socket and timeout errors to the caller', () {
    expect(
      networkErrorMessage(const SocketException('refused'), appLocalizations),
      isNull,
    );
    expect(
      networkErrorMessage(TimeoutException('core'), appLocalizations),
      isNull,
    );
    expect(networkErrorMessage(StateError('boom'), appLocalizations), isNull);
  });

  test('maps WebDAV status failures like any HTTP response', () {
    expect(
      networkErrorMessage(
        const DAVException(method: 'PUT', path: '/a', statusCode: 401),
        appLocalizations,
      ),
      appLocalizations.networkAccessDeniedError(401),
    );
  });

  test('maps Core request failures by their reason and status', () {
    expect(
      networkErrorMessage(
        const CoreMethodException(
          code: 'request_bad_response',
          message: '403 Forbidden',
          details: {'providerName': 'sub', 'statusCode': 403},
        ),
        appLocalizations,
      ),
      appLocalizations.networkAccessDeniedError(403),
    );
    expect(
      networkErrorMessage(
        const CoreMethodException(
          code: 'request_bad_response',
          message: '503 Service Unavailable',
        ),
        appLocalizations,
      ),
      appLocalizations.networkServerError(503),
    );
    expect(
      networkErrorMessage(
        const CoreMethodException(
          code: 'request_error',
          message: 'context deadline exceeded',
          details: {'reason': 'timeout'},
        ),
        appLocalizations,
      ),
      appLocalizations.networkTimeoutError,
    );
    expect(
      networkErrorMessage(
        const CoreMethodException(code: 'request_error', message: 'odd'),
        appLocalizations,
      ),
      appLocalizations.networkRequestFailed('odd'),
    );
  });

  test('uses the Core message for non-request failures', () {
    expect(
      userFacingErrorMessage(
        const CoreMethodException(
          code: 'provider_update_error',
          message: 'proxy 0: unsupported type',
        ),
        appLocalizations,
      ),
      'proxy 0: unsupported type',
    );
  });

  group('Dart-constructed Core errors name their cause', () {
    test('service start and stop failures differ', () {
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'service_refused',
            message: 'The iOS service did not start',
          ),
          appLocalizations,
        ),
        appLocalizations.serviceDidNotStart,
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'service_refused',
            message: 'The mobile service did not stop',
          ),
          appLocalizations,
        ),
        appLocalizations.serviceDidNotStop,
      );
    });

    test('Core availability and empty answers name the method', () {
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'core_unavailable',
            message: 'Core is not connected for core.setup',
          ),
          appLocalizations,
        ),
        appLocalizations.coreNotConnected('core.setup'),
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'empty_result',
            message: 'Core answered core.setup with nothing',
          ),
          appLocalizations,
        ),
        appLocalizations.coreAnsweredNothing('core.setup'),
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'core_unavailable',
            message: 'unexpected shape',
          ),
          appLocalizations,
        ),
        appLocalizations.coreUnavailable,
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'empty_result',
            message: 'unexpected shape',
          ),
          appLocalizations,
        ),
        appLocalizations.coreEmptyResult,
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'spill_error',
            message: 'unexpected shape',
          ),
          appLocalizations,
        ),
        appLocalizations.coreSpillOutsideDirectory,
      );
    });

    test('transport failures name their cause', () {
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'transport_disconnected',
            message: 'Core RPC client is closed',
          ),
          appLocalizations,
        ),
        appLocalizations.coreRpcClientClosed,
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'transport_disconnected',
            message: 'Core transport disconnected',
          ),
          appLocalizations,
        ),
        appLocalizations.coreTransportDisconnected,
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'transport_error',
            message: 'Unable to send core.setup to Core',
          ),
          appLocalizations,
        ),
        appLocalizations.coreSendFailed('core.setup'),
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'transport_error',
            message: 'Core transport failed',
          ),
          appLocalizations,
        ),
        appLocalizations.coreTransportFailed,
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'spill_error',
            message: 'Core wrote a file outside its spill directory: /tmp/x',
          ),
          appLocalizations,
        ),
        appLocalizations.spillOutsideDirectory('/tmp/x'),
      );
    });

    test('Core method timeouts name the method', () {
      expect(
        userFacingErrorMessage(
          TimeoutException('Core method core.setup timed out'),
          appLocalizations,
        ),
        appLocalizations.coreMethodTimedOut('core.setup'),
      );
      expect(
        userFacingErrorMessage(
          TimeoutException('something else'),
          appLocalizations,
        ),
        contains('something else'),
      );
    });

    test('script without a configuration object is localized', () {
      expect(
        userFacingErrorMessage(
          const MessageException(
            'script did not return a configuration object',
          ),
          appLocalizations,
        ),
        appLocalizations.scriptDidNotReturnConfig,
      );
    });
  });

  group('policy-blocked Core launch', () {
    const blocked = DesktopCoreFailure(
      code: 'start_failed',
      phase: DesktopCorePhase.starting,
      revision: 1,
      cause: HelperException(
        code: 'processLaunchFailed',
        message: 'spawn failed',
        details: {'osError': 577},
      ),
    );

    tearDown(() {
      smartAppControlStateReader = readSmartAppControlState;
    });

    test('names Smart App Control when it is on', () {
      smartAppControlStateReader = () => SmartAppControlState.on;

      expect(
        userFacingErrorMessage(blocked, appLocalizations),
        appLocalizations.coreBlockedBySmartAppControlTip,
      );
    });

    test('names the generic policy with its error code otherwise', () {
      smartAppControlStateReader = () => SmartAppControlState.off;

      expect(
        userFacingErrorMessage(blocked, appLocalizations),
        appLocalizations.coreBlockedByPolicyTip(577),
      );
    });

    test('other start failures name the failure', () {
      smartAppControlStateReader = () => SmartAppControlState.on;
      const timedOut = DesktopCoreFailure(
        code: 'start_failed',
        phase: DesktopCorePhase.starting,
        revision: 1,
        cause: HelperException(
          code: 'transportError',
          message: 'Helper start request failed',
        ),
      );

      expect(
        userFacingErrorMessage(timedOut, appLocalizations),
        appLocalizations.coreStartFailed,
      );
    });

    test('desktop lifecycle failures name the failure', () {
      final cases =
          <(String, DesktopCorePhase, String Function(AppLocalizations))>{
            ('stop_failed', DesktopCorePhase.stopping, (l) => l.coreStopFailed),
            (
              'transport_failed',
              DesktopCorePhase.running,
              (l) => l.coreTransportFailed,
            ),
            (
              'unexpected_disconnect',
              DesktopCorePhase.running,
              (l) => l.coreUnexpectedDisconnect,
            ),
            (
              'session_mismatch',
              DesktopCorePhase.starting,
              (l) => l.coreSessionMismatch,
            ),
            (
              'lifecycle_closed',
              DesktopCorePhase.closed,
              (l) => l.coreLifecycleClosed,
            ),
            (
              'lifecycle_error',
              DesktopCorePhase.starting,
              (l) => l.coreLifecycleError,
            ),
            (
              'peer_pid_mismatch',
              DesktopCorePhase.starting,
              (l) => l.corePeerPidMismatch,
            ),
            (
              'process_cleanup_failed',
              DesktopCorePhase.stopping,
              (l) => l.coreProcessCleanupFailed,
            ),
            (
              'process_exit_unconfirmed',
              DesktopCorePhase.stopping,
              (l) => l.coreProcessExitUnconfirmed,
            ),
          };
      for (final (code, phase, expected) in cases) {
        expect(
          userFacingErrorMessage(
            DesktopCoreFailure(code: code, phase: phase, revision: 1),
            appLocalizations,
          ),
          expected(appLocalizations),
        );
      }
    });

    test('Core method failures name the failure', () {
      final cases = <(String, String, String Function(AppLocalizations))>{
        ('start_failed', '', (l) => l.coreStartFailed),
        ('stop_failed', '', (l) => l.coreStopFailed),
        ('transport_failed', '', (l) => l.coreTransportFailed),
        ('unexpected_disconnect', '', (l) => l.coreUnexpectedDisconnect),
        ('session_mismatch', '', (l) => l.coreSessionMismatch),
        ('lifecycle_closed', '', (l) => l.coreLifecycleClosed),
        ('lifecycle_error', '', (l) => l.coreLifecycleError),
        ('peer_pid_mismatch', '', (l) => l.corePeerPidMismatch),
        ('process_cleanup_failed', '', (l) => l.coreProcessCleanupFailed),
        ('process_exit_unconfirmed', '', (l) => l.coreProcessExitUnconfirmed),
      };
      for (final (code, message, expected) in cases) {
        expect(
          userFacingErrorMessage(
            CoreMethodException(code: code, message: message),
            appLocalizations,
          ),
          expected(appLocalizations),
        );
      }
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'no_response',
            message: 'Core did not answer core.setup',
          ),
          appLocalizations,
        ),
        appLocalizations.coreDidNotAnswer('core.setup'),
      );
      expect(
        userFacingErrorMessage(
          const CoreMethodException(
            code: 'no_response',
            message: 'unexpected shape',
          ),
          appLocalizations,
        ),
        appLocalizations.coreNoResponse,
      );
    });
  });
}
