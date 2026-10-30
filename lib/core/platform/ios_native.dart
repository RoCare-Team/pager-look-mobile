import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A Home Screen quick action. [icon] is an SF Symbol name.
class IosShortcut {
  const IosShortcut({required this.route, required this.title, this.subtitle, this.icon});

  final String route;
  final String title;
  final String? subtitle;
  final String? icon;

  Map<String, String> toMap() => {
        'route': route,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle!,
        if (icon != null) 'icon': icon!,
      };
}

/// Bridge to the iOS-only native features in `ios/Runner/PagerLookNativePlugin.swift`:
/// Face ID / Touch ID, Home Screen quick actions and in-app Safari.
///
/// Every call is a no-op (or returns the "not available" value) on other
/// platforms, so Android behaviour is unchanged.
class IosNative {
  IosNative._();

  static const _channel = MethodChannel('com.pagerlook/ios_native');

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// `faceID`, `touchID`, or null when no biometrics are enrolled.
  static Future<String?> biometryType() async {
    if (!isSupported) return null;
    final type = await _call<String>('biometryType');
    return (type == null || type == 'none') ? null : type;
  }

  /// Face ID / Touch ID with passcode fallback. True when the user passed.
  static Future<bool> authenticate(String reason) async {
    if (!isSupported) return false;
    return await _call<bool>('authenticate', {'reason': reason}) ?? false;
  }

  /// Opens an http(s) link in SFSafariViewController over the app.
  /// False when it could not (non-iOS, other schemes), so callers can fall back.
  static Future<bool> openInApp(Uri uri) async {
    if (!isSupported || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    return await _call<bool>('openInApp', {'url': uri.toString()}) ?? false;
  }

  /// Replaces the dynamic quick actions (the static "Scan QR" item stays).
  static Future<void> setShortcuts(List<IosShortcut> items) async {
    if (!isSupported) return;
    await _call<void>('setShortcuts', items.map((s) => s.toMap()).toList());
  }

  /// Calls [onRoute] for the quick action that launched the app, and for every
  /// one picked while it runs.
  static Future<void> listenForShortcuts(void Function(String route) onRoute) async {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openShortcut' && call.arguments is String) onRoute(call.arguments as String);
    });
    final launch = await _call<String>('takeLaunchShortcut');
    if (launch != null && launch.isNotEmpty) onRoute(launch);
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
