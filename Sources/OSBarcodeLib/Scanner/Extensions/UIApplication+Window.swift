import UIKit

extension UIApplication {
    /// The application's main window.
    static var firstKeyWindowForConnectedScenes: UIWindow? {
        // 1. Use the modern, crash-free approach for iOS 15, 16, 17, and 18
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow
        }
        // 2. Safe fallback for older devices (iOS 14 and below)
        else {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
    }
}
