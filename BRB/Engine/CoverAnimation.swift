//
//  CoverAnimation.swift
//  BRB
//
//  Animated-GIF support for the veil cover image. SwiftUI's Image(nsImage:)
//  renders only the first frame, so frames + per-frame delays are decoded
//  here (ImageIO) and driven by TimelineView in AnimatedCoverView.swift.
//
//  Limitation: assumes full-size frames (true for virtually all exported
//  GIFs). Disposal-method compositing for delta frames is not implemented.
//

import AppKit
import ImageIO

/// One decoded GIF frame.
struct GIFFrame {
    var image: NSImage
    /// Display duration in seconds (browser-convention floor applied).
    var delay: TimeInterval

    /// Decodes all frames. Returns [] for non-GIFs and single-frame images
    /// so callers can fall back to the static path.
    static func decode(from data: Data) -> [GIFFrame] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return [] }
        var frames: [GIFFrame] = []
        frames.reserveCapacity(count)
        for i in 0 ..< count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
            let clamped = gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0
            var delay = unclamped > 0 ? unclamped : clamped
            if delay < 0.02 { delay = 0.1 }
            let size = NSSize(width: cg.width, height: cg.height)
            guard size.width > 0, size.height > 0 else { continue }
            frames.append(GIFFrame(image: NSImage(cgImage: cg, size: size), delay: delay))
        }
        return frames.count > 1 ? frames : []
    }
}
