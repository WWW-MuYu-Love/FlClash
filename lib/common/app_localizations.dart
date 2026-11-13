import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/network_error.dart';
import 'package:fl_clash/core/desktop/launch_policy.dart';
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
            _ => message,
          },
        CoreMethodException(code: 'empty_result', message: final message) =>
          switch (_segment(message, 'Core answered ', ' with nothing')) {
            final method? => appLocalizations.coreAnsweredNothing(method),
            _ => message,
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
            _ => message,
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
