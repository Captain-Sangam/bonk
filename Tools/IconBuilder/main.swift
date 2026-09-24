import AppKit
import Foundation

private enum IconBuilderError: LocalizedError {
    case usage
    case unreadableSource
    case renderingFailed(Int)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: BonkIconBuilder <source.png> <output.icns>"
        case .unreadableSource:
            return "The source icon could not be read."
        case let .renderingFailed(size):
            return "The \(size) px icon representation could not be rendered."
        }
    }
}

@main
private struct BonkIconBuilder {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else { throw IconBuilderError.usage }

        let sourceURL = URL(fileURLWithPath: arguments[0])
        let outputURL = URL(fileURLWithPath: arguments[1])
        guard let source = NSImage(contentsOf: sourceURL) else {
            throw IconBuilderError.unreadableSource
        }

        let representations: [(type: String, size: Int)] = [
            ("icp4", 16),
            ("icp5", 32),
            ("icp6", 64),
            ("ic07", 128),
            ("ic08", 256),
            ("ic09", 512),
            ("ic10", 1024)
        ]
        let payloads = try representations.map { representation in
            (
                type: representation.type,
                data: try renderPNG(source, size: representation.size)
            )
        }

        let totalLength = 8 + payloads.reduce(0) { $0 + 8 + $1.data.count }
        var iconData = Data("icns".utf8)
        iconData.appendBigEndianUInt32(totalLength)

        for payload in payloads {
            iconData.append(contentsOf: payload.type.utf8)
            iconData.appendBigEndianUInt32(payload.data.count + 8)
            iconData.append(payload.data)
        }

        try iconData.write(to: outputURL, options: .atomic)
        print("Created \(outputURL.path)")
    }

    private static func renderPNG(_ source: NSImage, size: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw IconBuilderError.renderingFailed(size)
        }

        bitmap.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        source.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw IconBuilderError.renderingFailed(size)
        }
        return png
    }
}

private extension Data {
    mutating func appendBigEndianUInt32(_ value: Int) {
        var encoded = UInt32(value).bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}
