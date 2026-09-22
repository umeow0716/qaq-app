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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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

