import AppKit

/// Portable SDR export, even when system bundle artwork supplies an HDR/PQ image.
/// Convert through a real sRGB context; changing the PNG's profile alone is incorrect.
enum StandardBitmap {
    static func make(_ image: CGImage) -> NSBitmapImageRep? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let standard = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: standard)
    }
}
