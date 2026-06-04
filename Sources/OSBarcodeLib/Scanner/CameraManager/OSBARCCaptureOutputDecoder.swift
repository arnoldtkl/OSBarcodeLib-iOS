import AudioToolbox
import AVFoundation
import Combine
import SwiftUI

/// Class responsible for decoding the scanning output (in this case, barcodes).
/// Uses `AVCaptureMetadataOutput` for native, thread-safe barcode detection.
/// This avoids the Vision framework's `VNDetectBarcodesRequest` reuse issues that
/// caused `EXC_BAD_ACCESS` crashes on iOS 17 physical devices.
final class OSBARCCaptureOutputDecoder: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    /// The object containing the value to return.
    @Binding private var scanResult: OSBARCScanResult
    /// Indicates if scanning should be done only after a button click or automatically.
    private let scanThroughButton: Bool
    /// Indicates if scanning is enabled (when there's a Scan Button).
    private var scanButtonEnabled: Bool
    /// A hint, to scan a specific format (e.g. only qr code). `Nil` or `unknown` value means it can scan all.
    private let hint: OSBARCScannerHint?

    /// Dedicated serial queue for the metadata output delegate.
    /// All reads and writes to mutable state happen here.
    let delegateQueue = DispatchQueue(label: "com.outsystems.osbarc.captureOutput", qos: .default)

    /// The `AVMetadataObject.ObjectType` values to detect, derived from the hint.
    var metadataObjectTypes: [AVMetadataObject.ObjectType] {
        (hint ?? .unknown).avMetadataObjectTypes
    }

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
            .publisher(for: .scanButtonSelection)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in // performed when `scanButtonSelection` gets triggered.
                guard let enabled = notification.object as? Bool else { return }
                // Route through delegateQueue so captureOutput reads are race-free.
                self?.delegateQueue.async { [weak self] in
                    self?.scanButtonEnabled = enabled
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Called on delegateQueue (the queue passed to setMetadataObjectsDelegate).
        guard !self.scanThroughButton || self.scanButtonEnabled else { return }
        guard let codeObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = codeObject.stringValue else { return }

        // Extract value types now, before dispatching to main, so we don't hold a
        // reference to the AVMetadataObject (an ObjC heap object) across threads.
        let objectType = codeObject.type    // struct – safe to escape
        // payload is a Swift String (value type copy) – safe to escape

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            let format = OSBARCScannerHint.fromAVMetadataObjectType(objectType, withHint: self.hint)
            self.scanResult = OSBARCScanResult(text: payload, format: format)
        }
    }
}

