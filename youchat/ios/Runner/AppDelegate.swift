import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Prevent screen recording and screenshots on iOS
    // Uses secure text field trick used by banking apps
    DispatchQueue.main.async {
      self.makeSecure()
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func makeSecure() {
    guard let window = self.window else { return }
    
    let field = UITextField()
    field.isSecureTextEntry = true
    window.addSubview(field)
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    window.layer.superlayer?.addSublayer(field.layer)
    field.layer.sublayers?.first?.addSublayer(window.layer)
  }
}
