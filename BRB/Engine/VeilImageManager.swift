//
//  VeilImageManager.swift
//  BRB
//
//  Manages the user-selected cover image, persistence via security-scoped bookmarks,
//  and procedural high-resolution fallback image generation.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@Observable
class VeilImageManager {
    static let shared = VeilImageManager()

    var customImage: NSImage?
    var isCustomImage: Bool = false
    var bookmarkError: String?

    /// Original file bytes (needed for GIF frame decoding; NSImage alone
    /// collapses animation to the first frame).
    var customImageData: Data?
    private var gifFrameCache: (data: Data, frames: [GIFFrame])?

    private let bookmarkKey = "BRB.veilImageBookmark"

    init() {
        loadImageFromBookmark()
    }

    /// Attempts to load and resolve the persisted security-scoped bookmark.
    func loadImageFromBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            customImage = nil
            customImageData = nil
            gifFrameCache = nil
            isCustomImage = false
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-save stale bookmark if possible
                saveBookmark(for: url)
            }

            guard url.startAccessingSecurityScopedResource() else {
                bookmarkError = "Permission denied accessing selected image."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                self.customImageData = data
                self.customImage = image
                self.gifFrameCache = nil
                self.isCustomImage = true
                self.bookmarkError = nil
            } else {
                self.bookmarkError = "Could not decode image at \(url.lastPathComponent)."
            }
        } catch {
            self.bookmarkError = "Failed to resolve saved image: \(error.localizedDescription)"
            self.customImage = nil
            self.customImageData = nil
            self.gifFrameCache = nil
            self.isCustomImage = false
        }
    }

    /// Presents standard NSOpenPanel for picking a veil cover image.
    func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .png,
            .jpeg,
            .tiff,
            .heic,
            .bmp,
            .gif
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Screen Cover (Veil) Image"

        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
            loadImageFromBookmark()
        }
    }

    /// Saves a security-scoped bookmark for the chosen file URL.
    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            bookmarkError = "Failed to create security-scoped bookmark: \(error.localizedDescription)"
        }
    }

    /// Clears the custom cover image and resets to the default wordmark gradient.
    func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        customImage = nil
        customImageData = nil
        gifFrameCache = nil
        isCustomImage = false
        bookmarkError = nil
    }

    /// Animated frames for the custom image, or nil when static / no custom
    /// image. Parsed once per file, then cached (decoding on every frame
    /// tick would be wasteful).
    func animatedFrames() -> [GIFFrame]? {
        guard let data = customImageData else { return nil }
        if let cache = gifFrameCache, cache.data == data {
            return cache.frames.isEmpty ? nil : cache.frames
        }
        let frames = GIFFrame.decode(from: data)
        gifFrameCache = (data, frames)
        return frames.isEmpty ? nil : frames
    }

    /// Returns the effective image: user chosen image or the crisp default asset.
    func effectiveImage(for size: CGSize = CGSize(width: 1920, height: 1080)) -> NSImage {
        if let custom = customImage {
            return custom
        }
        let renderWidth = size.width > 0 ? size.width : 1920
        let renderHeight = size.height > 0 ? size.height : 1080
        return defaultVeilImage(size: CGSize(width: renderWidth, height: renderHeight))
    }

    /// Generates a high-resolution dark gradient with the "BRB — stepped away" wordmark.
    func defaultVeilImage(size: CGSize) -> NSImage {
        let renderWidth = max(size.width, 320)
        let renderHeight = max(size.height, 240)
        let renderSize = CGSize(width: renderWidth, height: renderHeight)

        let image = NSImage(size: renderSize, flipped: false) { rect in
            // 1. Dark elegant gradient background
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0),
                NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.04, alpha: 1.0)
            ])
            gradient?.draw(in: rect, angle: -45.0)

            // Subtle vignette circle
            let centerPoint = NSPoint(x: rect.width / 2.0, y: rect.height / 2.0)
            let maxRadius = max(rect.width, rect.height) * 0.6
            let vignette = NSGradient(colors: [
                NSColor(calibratedWhite: 1.0, alpha: 0.04),
                NSColor.clear
            ])
            let vignettePath = NSBezierPath(ovalIn: NSRect(
                x: centerPoint.x - maxRadius,
                y: centerPoint.y - maxRadius,
                width: maxRadius * 2,
                height: maxRadius * 2
            ))
            vignette?.draw(in: vignettePath, relativeCenterPosition: .zero)

            // 2. "BRB" title
            let titleFont = NSFont.systemFont(ofSize: min(rect.width * 0.06, 72), weight: .bold)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor(white: 0.92, alpha: 1.0)
            ]
            let title = "BRB" as NSString
            let titleSize = title.size(withAttributes: titleAttributes)
            let titleRect = NSRect(
                x: (rect.width - titleSize.width) / 2.0,
                y: (rect.height / 2.0) + 10,
                width: titleSize.width,
                height: titleSize.height
            )
            title.draw(in: titleRect, withAttributes: titleAttributes)

            // 3. Subtitle
            let subtitleFont = NSFont.systemFont(ofSize: min(rect.width * 0.02, 22), weight: .medium)
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
            ]
            let subtitle = "Stepped away" as NSString
            let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
            let subtitleRect = NSRect(
                x: (rect.width - subtitleSize.width) / 2.0,
                y: titleRect.minY - subtitleSize.height - 12,
                width: subtitleSize.width,
                height: subtitleSize.height
            )
            subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)

            return true
        }

        return image
    }
}
