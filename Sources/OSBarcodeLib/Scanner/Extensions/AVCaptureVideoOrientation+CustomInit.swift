import AVFoundation
import UIKit

/// Extension that maps a `UIDeviceOrientation` into an `AVCaptureVideoOrientation`.
extension AVCaptureVideoOrientation {
    /// Mapper construtor.
    /// - Parameter interfaceOrientation: Value to be converted from.
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        case .unknown: return nil
        @unknown default: return nil
        }
    }
}

/// Extension that maps a `UIInterfaceOrientation` into a video rotation angle (degrees) for iOS 17+.
@available(iOS 17.0, *)
extension UIInterfaceOrientation {
    /// The video rotation angle in degrees corresponding to this interface orientation.
    /// Returns `nil` for unknown orientations.
    var videoRotationAngle: CGFloat? {
        switch self {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        case .unknown: return nil
        @unknown default: return nil
        }
    }
}
