import CoreGraphics
import Foundation
import ImageIO
import TCPluginSDK

import UniformTypeIdentifiers

/// Image properties as content fields (the WDX-equivalent surface): the
/// dimensions, orientation, resolution, colour model and depth a file manager
/// is expected to show as columns — sortable, searchable, and usable as
/// MultiRename `[=field]` placeholders.
///
/// It reads each file with ImageIO rather than asking Spotlight, because the
/// two differ where it matters: Spotlight answers only for indexed local
/// volumes, so its columns go blank on a network share, a freshly-attached
/// disk, or anything the index has not reached — while ImageIO reads the
/// file's own header. Only the header is read: `shouldCache: false` and no
/// decode, so a 100-megapixel RAW costs the same as a thumbnail.
public struct ImagePropertiesProvider: ContentProvider {
    public var providerID: String { "builtin.image" }

    public init() {}

    /// Field ids are namespaced `img.*` so they never collide with the
    /// Spotlight catalog's `md.*` or a third-party plugin's.
    enum Field: String, CaseIterable {
        case dimensions = "img.dimensions"
        case width = "img.width"
        case height = "img.height"
        case orientation = "img.orientation"
        case megapixels = "img.megapixels"
        case aspectRatio = "img.aspectRatio"
        case dpi = "img.dpi"
        case colorModel = "img.colorModel"
        case colorProfile = "img.colorProfile"
        case bitDepth = "img.bitDepth"
        case hasAlpha = "img.hasAlpha"
        case format = "img.format"
        case frameCount = "img.frameCount"

        var displayName: String {
            switch self {
            case .dimensions: return "Image Size" // l10n:exempt: boundary key
            case .width: return "Image Width" // l10n:exempt: boundary key
            case .height: return "Image Height" // l10n:exempt: boundary key
            case .orientation: return "Orientation" // l10n:exempt: boundary key
            case .megapixels: return "Megapixels" // l10n:exempt: boundary key
            case .aspectRatio: return "Aspect Ratio" // l10n:exempt: boundary key
            case .dpi: return "Resolution (DPI)" // l10n:exempt: boundary key
            case .colorModel: return "Color Model" // l10n:exempt: boundary key
            case .colorProfile: return "Color Profile" // l10n:exempt: boundary key
            case .bitDepth: return "Bit Depth" // l10n:exempt: boundary key
            case .hasAlpha: return "Has Transparency" // l10n:exempt: boundary key
            case .format: return "Image Format" // l10n:exempt: boundary key
            case .frameCount: return "Frame Count" // l10n:exempt: boundary key
            }
        }

        var kind: FieldDescriptor.Kind {
            switch self {
            case .width, .height, .dpi, .bitDepth, .frameCount: return .number
            case .megapixels: return .decimal
            case .hasAlpha: return .boolean
            case .dimensions, .orientation, .aspectRatio, .colorModel,
                 .colorProfile, .format: return .text
            }
        }
    }

    public func fields() -> [FieldDescriptor] {
        Field.allCases.map {
            FieldDescriptor(
                id: FieldID(rawValue: $0.rawValue), displayName: $0.displayName, kind: $0.kind)
        }
    }

    public func value(of field: FieldID, forFileAt url: URL) async throws -> FieldValue? {
        guard let field = Field(rawValue: field.rawValue) else { return nil }
        return Self.read(field, from: url)
    }

    // MARK: - Reading

    /// Header-only read. A file that is not an image, or is truncated, simply
    /// has no value for these fields — a blank cell, not an error, exactly
    /// like a file without an EXIF tag.
    static func read(_ field: Field, from url: URL) -> FieldValue? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
                as? [CFString: Any] else { return nil }

        switch field {
        case .frameCount:
            return .number(Int64(CGImageSourceGetCount(source)))
        case .format:
            guard let type = CGImageSourceGetType(source) as? String else { return nil }
            return .text(UTType(type)?.localizedDescription ?? type)
        default:
            return properties(field, raw)
        }
    }

    private static func properties(_ field: Field, _ raw: [CFString: Any]) -> FieldValue? {
        let width = (raw[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (raw[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue

        switch field {
        case .width:
            return width.map { .number(Int64($0)) }
        case .height:
            return height.map { .number(Int64($0)) }
        case .dimensions:
            guard let width, let height else { return nil }
            return .text("\(width) × \(height)") // l10n:exempt: dimensions format
        case .orientation:
            guard let width, let height else { return nil }
            return .text(orientationName(width: width, height: height))
        case .megapixels:
            guard let width, let height else { return nil }
            let megapixels = Double(width * height) / 1_000_000
            // The number sorts; the text is what the column shows.
            return .decimal(
                megapixels, display: String(format: "%.1f MP", megapixels))
        case .aspectRatio:
            guard let width, let height, width > 0, height > 0 else { return nil }
            return .text(aspectRatio(width: width, height: height))
        case .dpi:
            // DPI-per-axis differs only in exotic files; the width figure is
            // what every other tool shows.
            guard let dpi = (raw[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
                  dpi > 0 else { return nil }
            return .number(Int64(dpi.rounded()))
        case .colorModel:
            guard let model = raw[kCGImagePropertyColorModel] as? String else { return nil }
            return .text(model)
        case .colorProfile:
            guard let profile = raw[kCGImagePropertyProfileName] as? String else { return nil }
            return .text(profile)
        case .bitDepth:
            guard let depth = (raw[kCGImagePropertyDepth] as? NSNumber)?.intValue
            else { return nil }
            return .number(Int64(depth))
        case .hasAlpha:
            return .boolean((raw[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false)
        case .format, .frameCount:
            // Answered by `read` from the source itself, not this dictionary.
            return nil
        }
    }

    /// Portrait / Landscape / Square, from the pixel dimensions. Deliberately
    /// not the EXIF orientation tag: that says how the camera was held, and a
    /// rotated photo would then report Landscape while displaying portrait.
    /// ImageIO already reports width and height as they render.
    static func orientationName(width: Int, height: Int) -> String {
        if width > height { return "Landscape" } // l10n:exempt: boundary key
        if height > width { return "Portrait" } // l10n:exempt: boundary key
        return "Square" // l10n:exempt: boundary key
    }

    /// The ratio in lowest terms ("16 : 9"), which is how it is spoken about.
    /// Near-miss dimensions (1920×1081) would reduce to an unreadable ratio,
    /// so a close match to a common ratio wins.
    static func aspectRatio(width: Int, height: Int) -> String {
        let common: [(width: Int, height: Int)] = [
            (1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (185, 100), (239, 100), (21, 9)
        ]
        let ratio = Double(max(width, height)) / Double(min(width, height))
        let portrait = height > width
        for candidate in common {
            let target = Double(candidate.width) / Double(candidate.height)
            guard abs(ratio - target) / target < 0.02 else { continue }
            return portrait
                ? "\(candidate.height) : \(candidate.width)" // l10n:exempt: ratio format
                : "\(candidate.width) : \(candidate.height)" // l10n:exempt: ratio format
        }
        let divisor = greatestCommonDivisor(width, height)
        let (reducedWidth, reducedHeight) = (width / divisor, height / divisor)
        // A ratio that does not reduce is unreadable as integers — 1000 × 333
        // is "3 : 1" to a human, not "1000 : 333" — so fall back to a decimal
        // against 1 once the reduced numbers stop being ratio-shaped.
        guard max(reducedWidth, reducedHeight) > 50 else {
            return "\(reducedWidth) : \(reducedHeight)" // l10n:exempt: ratio format
        }
        return portrait
            ? String(format: "1 : %.2f", ratio)
            : String(format: "%.2f : 1", ratio)
    }

    private static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var (larger, smaller) = (abs(first), abs(second))
        while smaller != 0 { (larger, smaller) = (smaller, larger % smaller) }
        return max(larger, 1)
    }
}
