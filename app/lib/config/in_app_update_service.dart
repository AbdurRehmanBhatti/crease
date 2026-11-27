import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Google Play Core's Flexible In-App Updates flow on Android.
///
/// When a newer Play Store release is available, Android displays Google Play's
/// native half-page update sheet. If the user accepts, Play downloads the
/// update in the background and notifies [onUpdateDownloaded] once ready so the
/// app can offer a non-intrusive "Restart" action via [completeUpdate].
class InAppUpdateService {
  InAppUpdateService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'app.crease.crease/in_app_update';
  static final InAppUpdateService instance = InAppUpdateService();

  final MethodChannel _channel;
  VoidCallback? _onUpdateDownloaded;
  bool _initialized = false;
  bool _checkedThisSession = false;

  bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Registers the native callback handler once. Safe to call multiple times.
  void init({required VoidCallback onUpdateDownloaded}) {
    _onUpdateDownloaded = onUpdateDownloaded;
    if (_initialized || !_isSupportedPlatform) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Checks Play Store for a Flexible update (at most once per session unless
  /// [force] is true) and launches the native Play Store half-page sheet when
  /// an update is available.
  Future<String> checkForFlexibleUpdate({bool force = false}) async {
    if (!_isSupportedPlatform) return 'unsupported';
    if (_checkedThisSession && !force) return 'already_checked';
    _checkedThisSession = true;
    try {
      final status = await _channel.invokeMethod<String>(
        'checkForFlexibleUpdate',
      );
      return status ?? 'unavailable';
    } on MissingPluginException {
      return 'unavailable';
    } on PlatformException {
      return 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  /// Completes a downloaded Flexible update, installing it and restarting the
  /// app via Play Core.
  Future<bool> completeUpdate() async {
    if (!_isSupportedPlatform) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('completeUpdate');
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onUpdateDownloaded') {
      _onUpdateDownloaded?.call();
    }
  }
}
