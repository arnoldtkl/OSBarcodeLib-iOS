import AVFoundation
import Combine
import SwiftUI
import Vision

/// Class responsible for decoding the scanning output (in this case, barcodes).
final class OSBARCCaptureOutputDecoder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// The object containing the value to return.
    @Binding private var scanResult: OSBARCScanResult
    /// Indicates if scanning should be done only  after a button click or automatically.
    private let scanThroughButton: Bool
    /// Indicates if scanning is enabled (when there's a Scan Button).
    private var scanButtonEnabled: Bool
    /// A hint, to scan a specific format (e.g. only qr code). `Nil` or `unknown` value means it can scan all.
    private var hint: OSBARCScannerHint?
    /// Cached EXIF orientation updated on the main thread. Read from the capture queue (serial).
    private var cachedExifOrientation: CGImagePropertyOrientation = .rightMirrored

    /// The publisher's cancellable instance collector.
    private var cancellables: Set<AnyCancellable> = []
    
    /// Constructor.
    /// - Parameters:
    ///   - scanResult: Binding object with the value to return.
    ///   - scanThroughButton: Boolean indicating if scanning should be performed automatically or after clicking the Scan Button.
    ///   - scanButtonEnabled: Indicates if scanning has already been set on.
    ///   - hint: The optional hint, to scan a specific format (e.g. only qr code). `Nil` or `unknown` value means it can scan all.
    init(_ scanResult: Binding<OSBARCScanResult>, _ scanThroughButton: Bool, _ scanButtonEnabled: Bool = false, andHint hint: OSBARCScannerHint? = nil) {
        self._scanResult = scanResult
        self.scanThroughButton = scanThroughButton
        self.scanButtonEnabled = scanButtonEnabled
        self.hint = hint
        super.init()
        
        NotificationCenter.default
            .publisher(for: .scanFrameChanged)
            .receive(on: RunLoop.main)  // receive this on the main thread
            .sink { [weak self] notification in // performed this when `scanFrameChanged` gets triggered (on screen rotation).
                guard let self else { return }
                if let imageRect = notification.object as? CGRect, let regionOfInterest = self.scanRegionOfInterest(for: imageRect) {
                    self.detectBarcodeRequest.regionOfInterest = regionOfInterest   // update `regionOfInterest`
                }
                // Also refresh cached EXIF orientation while we're already on the main thread.
                self.cachedExifOrientation = Self.exifOrientation(
                    for: UIApplication.firstKeyWindowForConnectedScenes?.windowScene?.interfaceOrientation
                )
            }
            .store(in: &cancellables)
        
        NotificationCenter.default
            .publisher(for: .scanButtonSelection)
            .receive(on: RunLoop.main)  // receive this on the main thread
            .sink { [weak self] notification in // performed this when `scanButtonSelection` gets triggered.
                if let enabled = notification.object as? Bool {
                    self?.scanButtonEnabled = enabled
                }
            }
            .store(in: &cancellables)

        // Seed the cached orientation immediately so the first frames have a valid value.
        DispatchQueue.main.async { [weak self] in
            self?.cachedExifOrientation = Self.exifOrientation(
                for: UIApplication.firstKeyWindowForConnectedScenes?.windowScene?.interfaceOrientation
            )
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Output should only be processed when scanning is automatically or it has been enabled through the Scan Button.
        guard !self.scanThroughButton || self.scanButtonEnabled else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var requestOptions: [VNImageOption: Any] = [:]
        
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics: camData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: self.deviceExifOrientation(), options: requestOptions
        )
        try? imageRequestHandler.perform([self.detectBarcodeRequest])
    }
    
    /// Vision request to perform. It gets initialised only once and when needed.
    lazy private var detectBarcodeRequest: VNDetectBarcodesRequest = {
        let barcodeRequest = VNDetectBarcodesRequest(completionHandler: { [weak self] request, error in
            guard error == nil else { return }
            self?.processClassification(for: request)
        })
        barcodeRequest.symbologies = (self.hint ?? .unknown).toVNBarcodeSymbologies()
        
        return barcodeRequest
    }()
}

// MARK: - Private methods
private extension OSBARCCaptureOutputDecoder {
    /// Processes the Vision request to return the desired barcode value.
    /// - Parameter request: Vision request handler that performs image analysis.
    func processClassification(for request: VNRequest) {
        DispatchQueue.main.async {
            if let bestResult = request.results?.first as? VNBarcodeObservation, bestResult.confidence > 0.9, let payload = bestResult.payloadStringValue {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                let format = OSBARCScannerHint.fromVNBarcodeSymbology(bestResult.symbology, withHint: self.hint)
                self.scanResult = OSBARCScanResult(text: payload, format: format)
            }
        }
    }
    
    /// Projects a rectangle from image coordinates into normalized coordinates.
    /// The normalized coordinates is the format expected by Vision's Region of Interest.
    /// More detail on https://developer.apple.com/documentation/vision/vnimagebasedrequest/2877482-regionofinterest.
    /// - Parameter imageRect: The coordinates to convert
    /// - Returns: The converted coordinates. If can return `nil` if not able to fetch the screens bounds to base on.
    func scanRegionOfInterest(for imageRect: CGRect) -> CGRect? {
        guard let screenBounds = UIApplication.firstKeyWindowForConnectedScenes?.windowScene?.screen.bounds else { return nil }
        return VNNormalizedRectForImageRect(imageRect, Int(screenBounds.width), Int(screenBounds.height))
    }
    
    /// Returns the cached EXIF orientation for the current interface orientation.
    /// Updated on the main thread via `scanFrameChanged` notifications; safe to call from the capture queue.
    func deviceExifOrientation() -> CGImagePropertyOrientation {
        return cachedExifOrientation
    }

    /// Maps a `UIInterfaceOrientation` to the `CGImagePropertyOrientation` needed by Vision.
    /// Must only be called from the main thread.
    private static func exifOrientation(for interfaceOrientation: UIInterfaceOrientation?) -> CGImagePropertyOrientation {
        switch interfaceOrientation ?? .portrait {
        case .portrait:             return .rightMirrored
        case .portraitUpsideDown:   return .leftMirrored
        case .landscapeLeft:        return .upMirrored   // device top to the right
        case .landscapeRight:       return .downMirrored // device top to the left
        @unknown default:           return .rightMirrored
        }
    }
}
