import CoreGraphics
import Foundation
import ImageIO
import Testing
import TCPluginSDK
import UniformTypeIdentifiers
@testable import ImageInfoKit

/// Writes a real image file so the provider is tested against ImageIO's own
/// reading, not a stubbed dictionary.
private func makeImage(
    width: Int, height: Int, alpha: Bool = false, type: UTType = .png
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("img-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "png")")
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: info.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

private func value(_ id: String, _ url: URL) async throws -> FieldValue? {
    try await ImagePropertiesProvider().value(of: FieldID(rawValue: id), forFileAt: url)
}

@Suite("Image properties as content fields")
struct ImagePropertiesProviderTests {
    @Test("every declared field has a name and a type")
    func catalog() {
        let fields = ImagePropertiesProvider().fields()
        #expect(fields.count == 13)
        #expect(fields.allSatisfy { !$0.displayName.isEmpty })
        #expect(fields.contains { $0.id.rawValue == "img.orientation" && $0.kind == .text })
        #expect(fields.contains { $0.id.rawValue == "img.megapixels" && $0.kind == .decimal })
        #expect(fields.contains { $0.id.rawValue == "img.hasAlpha" && $0.kind == .boolean })
        #expect(fields.contains { $0.id.rawValue == "img.width" && $0.kind == .number })
        // Ids are namespaced so they cannot collide with Spotlight's or a
        // third-party plugin's.
        #expect(fields.allSatisfy { $0.id.rawValue.hasPrefix("img.") })
    }

    @Test("a landscape image reports its size, orientation, and megapixels")
    func landscape() async throws {
        let url = try makeImage(width: 4032, height: 3024)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await value("img.width", url) == .number(4032))
        #expect(try await value("img.height", url) == .number(3024))
        #expect(try await value("img.dimensions", url) == .text("4032 × 3024"))
        #expect(try await value("img.orientation", url) == .text("Landscape"))
        #expect(try await value("img.aspectRatio", url) == .text("4 : 3"))
        // The number sorts, the display string is what the column shows.
        guard case .decimal(let megapixels, let display)? = try await value("img.megapixels", url)
        else {
            Issue.record("expected a decimal megapixel value")
            return
        }
        #expect(abs(megapixels - 12.19) < 0.01)
        #expect(display == "12.2 MP")
    }

    @Test("portrait and square are distinguished from landscape")
    func orientations() async throws {
        let portrait = try makeImage(width: 600, height: 900)
        let square = try makeImage(width: 512, height: 512)
        defer {
            try? FileManager.default.removeItem(at: portrait)
            try? FileManager.default.removeItem(at: square)
        }
        #expect(try await value("img.orientation", portrait) == .text("Portrait"))
        #expect(try await value("img.orientation", square) == .text("Square"))
        #expect(try await value("img.aspectRatio", portrait) == .text("2 : 3"))
        #expect(try await value("img.aspectRatio", square) == .text("1 : 1"))
    }

    @Test("colour model, depth, transparency, and format are read from the file")
    func colorAndFormat() async throws {
        let opaque = try makeImage(width: 10, height: 10)
        let transparent = try makeImage(width: 10, height: 10, alpha: true)
        defer {
            try? FileManager.default.removeItem(at: opaque)
            try? FileManager.default.removeItem(at: transparent)
        }
        #expect(try await value("img.colorModel", opaque) == .text("RGB"))
        #expect(try await value("img.bitDepth", opaque) == .number(8))
        #expect(try await value("img.hasAlpha", opaque) == .boolean(false))
        #expect(try await value("img.hasAlpha", transparent) == .boolean(true))
        #expect(try await value("img.frameCount", opaque) == .number(1))
        if case .text(let format)? = try await value("img.format", opaque) {
            #expect(format.localizedCaseInsensitiveContains("png"))
        } else {
            Issue.record("expected a format name")
        }
    }

    @Test("a JPEG is read as well as a PNG — the reader is format-agnostic")
    func jpeg() async throws {
        let url = try makeImage(width: 1920, height: 1080, type: .jpeg)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await value("img.dimensions", url) == .text("1920 × 1080"))
        #expect(try await value("img.aspectRatio", url) == .text("16 : 9"))
    }

    @Test("a file that is not an image has no values, and does not error")
    func notAnImage() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString).txt")
        try Data("plain text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        for field in ["img.width", "img.dimensions", "img.orientation", "img.hasAlpha"] {
            #expect(try await value(field, url) == nil)
        }
        // A missing file behaves the same way: a blank cell, never a throw.
        #expect(try await value("img.width", url.appendingPathExtension("gone")) == nil)
    }

    @Test("aspect ratios snap to the common ones, and reduce otherwise")
    func aspectRatioNaming() {
        #expect(ImagePropertiesProvider.aspectRatio(width: 1920, height: 1080) == "16 : 9")
        // One pixel off a common ratio must still read as that ratio, not
        // as 1920 : 1081.
        #expect(ImagePropertiesProvider.aspectRatio(width: 1920, height: 1081) == "16 : 9")
        #expect(ImagePropertiesProvider.aspectRatio(width: 3024, height: 4032) == "3 : 4")
        // Nothing common, but it reduces to ratio-shaped numbers.
        #expect(ImagePropertiesProvider.aspectRatio(width: 1000, height: 700) == "10 : 7")
        // Nothing common and it will not reduce: "1000 : 333" says nothing,
        // so it is expressed against 1.
        #expect(ImagePropertiesProvider.aspectRatio(width: 1000, height: 333) == "3.00 : 1")
        #expect(ImagePropertiesProvider.aspectRatio(width: 333, height: 1000) == "1 : 3.00")
    }

    @Test("orientation is named from the rendered dimensions")
    func orientationNaming() {
        #expect(ImagePropertiesProvider.orientationName(width: 100, height: 50) == "Landscape")
        #expect(ImagePropertiesProvider.orientationName(width: 50, height: 100) == "Portrait")
        #expect(ImagePropertiesProvider.orientationName(width: 50, height: 50) == "Square")
    }
}
