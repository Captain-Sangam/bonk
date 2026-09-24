import AppKit
import SwiftUI

public enum BonkBrandAssets {
    public static let foxLogo = loadImage(named: "bonk-fox-logo")
    public static let appIcon = loadImage(named: "bonk-app-icon")

    private static func loadImage(named name: String) -> NSImage? {
        let packagedURL = Bundle.main.resourceURL?
            .appendingPathComponent("Bonk_BonkCore.bundle", isDirectory: true)
            .appendingPathComponent("\(name).png")
        let resourceURL: URL?
        if let packagedURL, FileManager.default.fileExists(atPath: packagedURL.path) {
            resourceURL = packagedURL
        } else {
            resourceURL = Bundle.module.url(forResource: name, withExtension: "png")
        }

        guard let resourceURL else { return nil }
        return NSImage(contentsOf: resourceURL)
    }
}

public struct BonkLogoView: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let logo = BonkBrandAssets.foxLogo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}

public struct BonkAppIconView: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let icon = BonkBrandAssets.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                BonkLogoView(size: size)
            }
        }
        .frame(width: size, height: size)
    }
}
