import SwiftUI
#if os(iOS)
import UIKit

/// UIImage on the iPhone, NSImage on the Mac, so shared code (artist photos) works on both.
typealias PlatformImage = UIImage
#else
import AppKit
import ImageIO

typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// The few image operations the shared code needs, done the native way on each platform.
enum PlatformImages {
    /// An image from the app's asset catalog.
    static func named(_ name: String) -> PlatformImage? {
        #if os(iOS)
        UIImage(named: name)
        #else
        NSImage(named: name)
        #endif
    }

    static func decode(_ data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }

    /// Width × height in pixels.
    static func pixelSize(of image: PlatformImage) -> CGSize {
        #if os(iOS)
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #else
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
        #endif
    }

    /// Scales an image down so its longest side is `longest` pixels (returns the same image if it's
    /// already small enough).
    static func downsized(_ image: PlatformImage, longest target: CGFloat) -> PlatformImage {
        let pixels = pixelSize(of: image)
        let longest = max(pixels.width, pixels.height)
        guard longest > target * 1.05 else { return image }
        let factor = target / longest
        let size = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        #if os(iOS)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let scaled = context.makeImage() else { return image }
        return NSImage(cgImage: scaled, size: size)
        #endif
    }

    static func jpegData(_ image: PlatformImage, quality: CGFloat) -> Data? {
        #if os(iOS)
        image.jpegData(compressionQuality: quality)
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    /// Decoded ahead of time, so drawing it never stalls scrolling.
    static func preparedForDisplay(_ image: PlatformImage) async -> PlatformImage {
        #if os(iOS)
        await image.byPreparingForDisplay() ?? image
        #else
        // NSImage made from a CGImage that's already decoded draws straight away.
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        return NSImage(cgImage: cgImage, size: image.size)
        #endif
    }
}
