import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/network_error.dart';
import 'package:fl_clash/core/desktop/launch_policy.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/l10n.dart';

final currentAppLocalizations = AppLocalizations.current;

class AppUiLocalizations implements UiLocalizations {
  const AppUiLocalizations(this._localizations);

  static const LocalizationsDelegate<UiLocalizations> delegate =
      _AppUiLocalizationsDelegate();

  final AppLocalizations _localizations;

  @override
  String get back => _localizations.back;

  @override
  String get cancel => _localizations.cancel;

  @override
  String get clearSearch => _localizations.clearSearch;

  @override
  String get close => _localizations.close;

  @override
  String get copy => _localizations.copy;

  @override
  String get cut => _localizations.cut;

  @override
  String get hidePassword => _localizations.hidePassword;

  @override
  String get dialog => _localizations.dialog;

  @override
  String get more => _localizations.more;

  @override
  String get noSearchResults => _localizations.noSearchResults;

  @override
  String get paste => _localizations.paste;

  @override
  String get reset => _localizations.reset;

  @override
  String get search => _localizations.search;

  @override
  String get select => _localizations.select;

  @override
  String get selectAll => _localizations.selectAll;

  @override
  String get showLess => _localizations.showLess;

  @override
  String get showMore => _localizations.showMore;

  @override
  String get showPassword => _localizations.showPassword;

  @override
  String get sort => _localizations.sort;

  @override
  String get submit => _localizations.submit;
}

class _AppUiLocalizationsDelegate
    extends LocalizationsDelegate<UiLocalizations> {
  const _AppUiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<UiLocalizations> load(Locale locale) =>
      AppLocalizations.load(locale).then(AppUiLocalizations.new);

  @override
  bool shouldReload(_AppUiLocalizationsDelegate old) => false;
}

String? coreLaunchBlockedMessage(
  Object error,
  AppLocalizations appLocalizations,
) {
  if (!isPolicyBlockedLaunch(error)) {
    return null;
  }
  return switch (smartAppControlStateReader()) {
    SmartAppControlState.on || SmartAppControlState.evaluation =>
      appLocalizations.coreBlockedBySmartAppControlTip,
    _ => appLocalizations.coreBlockedByPolicyTip(launchOsError(error)!),
  };
}

String userFacingErrorMessage(Object error, AppLocalizations appLocalizations) {
  return networkErrorMessage(error, appLocalizations) ??
      coreLaunchBlockedMessage(error, appLocalizations) ??
      switch (error) {
        AgeSecretKeyRequiredException() =>
          appLocalizations.ageSecretKeyRequiredTip,
        ReleaseNotVerifiedException() => appLocalizations.updateNotVerified,
        SystemDownloadException() => appLocalizations.updateDownloadFailed,
        MessageException(
          message: 'script did not return a configuration object',
        ) =>
          appLocalizations.scriptDidNotReturnConfig,
        CoreMethodException(code: 'rule_set_empty') =>
          appLocalizations.ruleSetEmptyTip,
        CoreMethodException(code: 'rule_set_mixed') =>
          appLocalizations.ruleSetMixedTip,
        CoreMethodException(code: 'rule_set_invalid') =>
          appLocalizations.ruleSetInvalidTip,
        CoreMethodException(code: 'service_refused', message: final message) =>
          message.contains('did not stop')
              ? appLocalizations.serviceDidNotStop
              : appLocalizations.serviceDidNotStart,
        CoreMethodException(code: 'core_unavailable', message: final message) =>
          switch (_segment(message, 'Core is not connected for ', '')) {
            final method? => appLocalizations.coreNotConnected(method),
            _ => appLocalizations.coreUnavailable,
          },
        CoreMethodException(code: 'empty_result', message: final message) =>
          switch (_segment(message, 'Core answered ', ' with nothing')) {
            final method? => appLocalizations.coreAnsweredNothing(method),
            _ => appLocalizations.coreEmptyResult,
          },
        CoreMethodException(
          code: 'transport_disconnected',
          message: final message,
        ) =>
          message.contains('closed')
              ? appLocalizations.coreRpcClientClosed
              : appLocalizations.coreTransportDisconnected,
        CoreMethodException(code: 'transport_error', message: final message) =>
          switch (_segment(message, 'Unable to send ', ' to Core')) {
            final method? => appLocalizations.coreSendFailed(method),
            _ => appLocalizations.coreTransportFailed,
          },
        CoreMethodException(code: 'spill_error', message: final message) =>
          switch (_segment(
            message,
            'Core wrote a file outside its spill directory: ',
            '',
          )) {
            final path? => appLocalizations.spillOutsideDirectory(path),
            _ => appLocalizations.coreSpillOutsideDirectory,
          },
        CoreMethodException(code: 'start_failed') =>
          appLocalizations.coreStartFailed,
        CoreMethodException(code: 'stop_failed') =>
          appLocalizations.coreStopFailed,
        CoreMethodException(code: 'transport_failed') =>
          appLocalizations.coreTransportFailed,
        CoreMethodException(code: 'unexpected_disconnect') =>
          appLocalizations.coreUnexpectedDisconnect,
        CoreMethodException(code: 'no_response', message: final message) =>
          switch (_segment(message, 'Core did not answer ', '')) {
            final method? => appLocalizations.coreDidNotAnswer(method),
            _ => appLocalizations.coreNoResponse,
          },
        CoreMethodException(code: 'session_mismatch') =>
          appLocalizations.coreSessionMismatch,
        CoreMethodException(code: 'lifecycle_closed') =>
          appLocalizations.coreLifecycleClosed,
        CoreMethodException(code: 'lifecycle_error') =>
          appLocalizations.coreLifecycleError,
        CoreMethodException(code: 'peer_pid_mismatch') =>
          appLocalizations.corePeerPidMismatch,
        CoreMethodException(code: 'process_cleanup_failed') =>
          appLocalizations.coreProcessCleanupFailed,
        CoreMethodException(code: 'process_exit_unconfirmed') =>
          appLocalizations.coreProcessExitUnconfirmed,
        CoreMethodException(
          code: 'extension_config_failed',
          message: final message,
        ) =>
          switch (_segment(
            message,
            'App core applied the config, but the extension core did not receive it: ',
            '',
          )) {
            final reason? => appLocalizations.extensionConfigFailed(reason),
            _ => appLocalizations.extensionConfigNotReceived,
          },
        DesktopCoreFailure(:final code) => switch (code) {
          'start_failed' => appLocalizations.coreStartFailed,
          'stop_failed' => appLocalizations.coreStopFailed,
          'transport_failed' => appLocalizations.coreTransportFailed,
          'unexpected_disconnect' => appLocalizations.coreUnexpectedDisconnect,
          'session_mismatch' => appLocalizations.coreSessionMismatch,
          'lifecycle_closed' => appLocalizations.coreLifecycleClosed,
          'lifecycle_error' => appLocalizations.coreLifecycleError,
          'peer_pid_mismatch' => appLocalizations.corePeerPidMismatch,
          'process_cleanup_failed' => appLocalizations.coreProcessCleanupFailed,
          'process_exit_unconfirmed' =>
            appLocalizations.coreProcessExitUnconfirmed,
          _ => error.toString(),
        },
        TimeoutException(:final message) => switch (message) {
          final text?
              when text.startsWith('Core method ') &&
                  text.endsWith(' timed out') =>
            appLocalizations.coreMethodTimedOut(
              text.substring(
                'Core method '.length,
                text.length - ' timed out'.length,
              ),
            ),
          _ => error.toString(),
        },
        CoreMethodException(:final message) => message,
        _ => error.toString(),
      };
}

/// A diagnosed iOS tunnel start failure: a code the app localizes plus
/// the underlying detail text for the generic fallbacks. The code comes
/// from the Runner, which classifies the NEVPNError behind the failure.
typedef TunnelStartFailure = ({String code, String detail});

String tunnelStartFailureMessage(
  TunnelStartFailure failure,
  AppLocalizations appLocalizations,
) {
  return switch (failure.code) {
    'config_invalid' => appLocalizations.tunnelStartConfigInvalid,
    'config_disabled' => appLocalizations.tunnelStartConfigDisabled,
    'extension_failed' => appLocalizations.tunnelStartExtensionFailed(
      failure.detail,
    ),
    'not_started' =>
      failure.detail.isEmpty
          ? appLocalizations.tunnelStartNotStarted
          : appLocalizations.tunnelStartNotStartedDetail(failure.detail),
    _ =>
      failure.detail.isEmpty
          ? appLocalizations.tunnelStartFailed
          : appLocalizations.tunnelStartFailedDetail(failure.detail),
  };
}

/// The variable segment of a Dart-constructed core error message, or null
/// when the message does not match the shape its throw site builds.
String? _segment(String message, String prefix, String suffix) {
  if (!message.startsWith(prefix) || !message.endsWith(suffix)) {
    return null;
  }
  final inner = message.substring(
    prefix.length,
    message.length - suffix.length,
  );
  return inner.isEmpty ? null : inner;
}

String delayFailureText(int delay, AppLocalizations appLocalizations) {
  return delay == delayTimedOutValue
      ? appLocalizations.timeout
      : appLocalizations.delayFailed;
}

Locale? getLocaleForString(String? localString) {
  if (localString == null) return null;
  final localSplit = localString.split('_');
  if (localSplit.length == 1) {
    return Locale(localSplit[0]);
  }
  if (localSplit.length == 2) {
    return Locale(localSplit[0], localSplit[1]);
  }
  if (localSplit.length == 3) {
    return Locale.fromSubtags(
      languageCode: localSplit[0],
      scriptCode: localSplit[1],
      countryCode: localSplit[2],
    );
  }
  return null;
}
