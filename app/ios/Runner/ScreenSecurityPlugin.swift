import Flutter
import UIKit

/// Screen-content protection for iOS.
///
/// iOS does not allow apps to block screenshots, so we use the established
/// "secure text field layer" technique: the window's layer is re-parented into
/// the secure canvas of a `UITextField` with `isSecureTextEntry = true`, which
/// the system excludes from screenshots and recordings (they come out blank).
/// Screen recording / mirroring is additionally reported to Flutter, which
/// covers the UI with a privacy shield while capture is active.
final class ScreenSecurityPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ScreenSecurityPlugin()
    let channel = FlutterMethodChannel(name: "io.prostuti.app/screen_security", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)

    NotificationCenter.default.addObserver(
      instance, selector: #selector(captureChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(
      instance, selector: #selector(secureWindows),
      name: UIScene.didActivateNotification, object: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { instance.secureWindows() }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isCaptured":
      result(UIScreen.main.isCaptured)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func captureChanged() {
    channel?.invokeMethod("captureChanged", arguments: UIScreen.main.isCaptured)
  }

  @objc private func secureWindows() {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows { window.prostutiMakeSecure() }
    }
  }
}

private let secureFieldTag = 0x5EC0_4E

extension UIWindow {
  /// Idempotent: runs once per window.
  func prostutiMakeSecure() {
    if viewWithTag(secureFieldTag) != nil { return }
    let field = UITextField()
    field.tag = secureFieldTag
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.translatesAutoresizingMaskIntoConstraints = false
    addSubview(field)
    field.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    field.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
    layer.superlayer?.addSublayer(field.layer)
    if #available(iOS 17.0, *) {
      field.layer.sublayers?.last?.addSublayer(layer)
    } else {
      field.layer.sublayers?.first?.addSublayer(layer)
    }
  }
}
