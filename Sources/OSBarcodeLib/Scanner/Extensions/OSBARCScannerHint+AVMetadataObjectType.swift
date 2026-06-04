import AVFoundation

extension OSBARCScannerHint {
    /// The `AVMetadataObject.ObjectType` values that correspond to this hint.
    /// `.unknown` (or `nil` hint) returns all supported types.
    var avMetadataObjectTypes: [AVMetadataObject.ObjectType] {
        if let specific = Self.avTypeMappings[self] {
            return specific
        }
        // .unknown = scan all supported types
        return Self.avTypeMappings.values.flatMap { $0 }
    }

    /// Maps an `AVMetadataObject.ObjectType` back to the corresponding `OSBARCScannerHint`.
    static func fromAVMetadataObjectType(_ type: AVMetadataObject.ObjectType, withHint hint: OSBARCScannerHint? = nil) -> OSBARCScannerHint {
        if type == .ean13 {
            // UPC-A and EAN-13 share the same AVMetadata type; honour the caller's hint.
            switch hint {
            case .upcA:  return .upcA
            case .ean13: return .ean13
            default: break
            }
        }
        return Self.avTypeMappings.first { $0.value.contains(type) }?.key ?? .unknown
    }

    // MARK: - Private

    private static let avTypeMappings: [OSBARCScannerHint: [AVMetadataObject.ObjectType]] = {
        var result: [OSBARCScannerHint: [AVMetadataObject.ObjectType]] = [
            .qrCode:     [.qr],
            .aztec:      [.aztec],
            .code39:     [.code39, .code39Mod43],
            .code93:     [.code93],
            .code128:    [.code128],
            .dataMatrix: [.dataMatrix],
            .itf:        [.itf14, .interleaved2of5],
            .ean13:      [.ean13],
            .ean8:       [.ean8],
            .pdf417:     [.pdf417],
            .upcA:       [.ean13],  // UPC-A is encoded as EAN-13 with a leading 0
            .upcE:       [.upce],
        ]
        // codabar, GS1 DataBar variants are iOS 15.4+
        if #available(iOS 15.4, *) {
            result[.codabar]     = [.codabar]
            result[.rss14]       = [.gs1DataBar]
            result[.rssExpanded] = [.gs1DataBarExpanded]
        }
        return result
    }()
}
