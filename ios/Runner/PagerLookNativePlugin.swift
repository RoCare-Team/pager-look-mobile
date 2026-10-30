import Flutter
import LocalAuthentication
import SafariServices
import UIKit

/// iOS-only native features, reached from Dart through `lib/core/platform/ios_native.dart`:
///
/// * Face ID / Touch ID app lock (LocalAuthentication, with passcode fallback)
/// * Home Screen quick actions (static item in Info.plist + per-role dynamic items)
/// * Links and documents opened in-app with SFSafariViewController instead of Safari
final class PagerLookNativePlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static let channelName = "com.pagerlook/ios_native"

  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?

  /// Route of a quick action picked before Dart was listening (cold launch).
  private var pendingShortcutRoute: String?
  private var dartListening = false

  private init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = PagerLookNativePlugin(channel: channel, registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  // MARK: - Method channel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "biometryType":
      result(biometryType())
    case "authenticate":
      authenticate(reason: args["reason"] as? String ?? "Unlock PagerLook", result: result)
    case "openInApp":
      result(openInApp(args["url"] as? String))
    case "setShortcuts":
      setShortcuts(call.arguments as? [[String: Any]] ?? [])
      result(nil)
    case "takeLaunchShortcut":
      dartListening = true
      result(pendingShortcutRoute)
      pendingShortcutRoute = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Face ID / Touch ID

  private func biometryType() -> String {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return "none"
    }
    switch context.biometryType {
    case .faceID: return "faceID"
    case .touchID: return "touchID"
    default: return "none"
    }
  }

  /// `.deviceOwnerAuthentication` falls back to the device passcode, so a failed
  /// face scan never locks the user out of their own data.
  private func authenticate(reason: String, result: @escaping FlutterResult) {
    let context = LAContext()
    context.localizedFallbackTitle = "Use Passcode"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      result(false)
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
      DispatchQueue.main.async { result(success) }
    }
  }

  // MARK: - In-app Safari

  private func openInApp(_ urlString: String?) -> Bool {
    guard let urlString = urlString,
          let url = URL(string: urlString),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          let presenter = topViewController()
    else { return false }

    let safari = SFSafariViewController(url: url)
    safari.dismissButtonStyle = .close
    safari.preferredControlTintColor = UIColor(red: 0x15 / 255, green: 0x27 / 255, blue: 0x63 / 255, alpha: 1)
    presenter.present(safari, animated: true)
    return true
  }

  private func topViewController() -> UIViewController? {
    var top = registrar?.viewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  // MARK: - Home Screen quick actions

  /// Each item is `{route, title, subtitle?, icon?}`; `icon` is an SF Symbol name.
  /// The shortcut's `type` is the app route it opens.
  private func setShortcuts(_ items: [[String: Any]]) {
    UIApplication.shared.shortcutItems = items.compactMap { item in
      guard let route = item["route"] as? String, let title = item["title"] as? String else { return nil }
      let icon = (item["icon"] as? String).map { UIApplicationShortcutIcon(systemImageName: $0) }
      return UIApplicationShortcutItem(
        type: route,
        localizedTitle: title,
        localizedSubtitle: item["subtitle"] as? String,
        icon: icon,
        userInfo: nil
      )
    }
  }

  private func deliverShortcut(_ route: String) {
    if dartListening {
      channel.invokeMethod("openShortcut", arguments: route)
    } else {
      pendingShortcutRoute = route
    }
  }

  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let shortcut = connectionOptions?.shortcutItem {
      deliverShortcut(shortcut.type)
    }
    // Not consumed: other plugins still need the connection options.
    return false
  }

  @objc(windowScene:performActionForShortcutItem:completionHandler:)
  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) -> Bool {
    deliverShortcut(shortcutItem.type)
    completionHandler(true)
    return true
  }
}
