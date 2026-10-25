import UIKit
import Flutter
import UserNotifications
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    if(!UserDefaults.standard.bool(forKey: "Notification")) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.set(true, forKey: "Notification")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "qaq/global",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "set_webview_cookie":
        Self.setWebViewCookie(call, result: result)
      case "share_file":
        self.shareFile(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func shareFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(FlutterError(code: "INVALID_SHARE_PATH", message: "A file path is required.", details: nil))
      return
    }

    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "SHARE_FILE_NOT_FOUND", message: "The file does not exist.", details: nil))
      return
    }

    DispatchQueue.main.async {
      guard let presenter = Self.topViewController() else {
        result(FlutterError(code: "SHARE_FILE_FAILED", message: "Unable to find a view controller.", details: nil))
        return
      }

      let controller = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 1,
          height: 1
        )
        popover.permittedArrowDirections = []
      }
      presenter.present(controller, animated: true) {
        result(true)
      }
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let root = scenes
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController

    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    if let navigation = current as? UINavigationController {
      return navigation.visibleViewController ?? navigation
    }
    if let tab = current as? UITabBarController {
      return tab.selectedViewController ?? tab
    }
    return current
  }

  private static func setWebViewCookie(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let url = arguments["url"] as? String,
      let name = arguments["name"] as? String,
      let value = arguments["value"] as? String,
      let path = arguments["path"] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_COOKIE_ARGUMENTS",
          message: "A cookie URL, name, value and path are required.",
          details: nil
        )
      )
      return
    }

    var properties: [HTTPCookiePropertyKey: Any] = [
      .originURL: url,
      .name: name,
      .value: value,
      .path: path,
    ]

    if let domain = arguments["domain"] as? String {
      properties[.domain] = domain
    }
    if let expiresDate = arguments["expiresDate"] as? NSNumber {
      properties[.expires] = Date(timeIntervalSince1970: expiresDate.doubleValue / 1000.0)
    }
    if let maxAge = arguments["maxAge"] as? NSNumber {
      properties[.maximumAge] = maxAge.stringValue
    }
    if arguments["isSecure"] as? Bool == true {
      properties[.secure] = "TRUE"
    }
    if arguments["isHttpOnly"] as? Bool == true {
      properties[HTTPCookiePropertyKey("HttpOnly")] = "YES"
    }

    guard let cookie = HTTPCookie(properties: properties) else {
      result(false)
      return
    }

    WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
      result(true)
    }
  }

}

