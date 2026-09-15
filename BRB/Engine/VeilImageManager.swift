//
//  VeilImageManager.swift
//  BRB
//
//  Manages the screen cover (veil) image, security-scoped bookmark persistence,
//  and procedural fallback rendering.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@Observable
class VeilImageManager {
    static let shared = VeilImageManager()

    var customImage: NSImage?
    var isCustomImage: Bool = false
    var bookmarkError: String?

    private let bookmarkKey = "BRB.veilImageBookmark"

    init() {
        loadImageFromBookmark()
    }

    /// Loads the persisted cover image from a security-scoped bookmark.
    func loadImageFromBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            customImage = nil
            isCustomImage = false
            bookmarkError = nil
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard url.startAccessingSecurityScopedResource() else {
                bookmarkError = "Permission to access saved image was denied."
                customImage = nil
                isCustomImage = false
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            if let img = NSImage(contentsOf: url) {
                self.customImage = img
                self.isCustomImage = true
                self.bookmarkError = nil

                // Update bookmark if marked stale
                if isStale {
                    saveBookmark(for: url)
                }
            } else {
                bookmarkError = "Could not decode saved image file."
                customImage = nil
                isCustomImage = false
            }
        } catch {
            bookmarkError = "Saved image bookmark is invalid (\(error.localizedDescription))."
            customImage = nil
            isCustomImage = false
        }
    }

    /// Presents an open panel for selecting an image file and saves a security-scoped bookmark.
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
        isCustomImage = false
        bookmarkError = nil
    }

    /// Returns the effective image: user chosen image or the crisp default asset.
    func effectiveImage(for size: CGSize = CGSize(width: 1920, height: 1080)) -> NSImage {
        if let custom = customImage {
            return custom
        }
        return defaultVeilImage(size: size)
    }

    /// Generates a high-resolution dark gradient with the "BRB — stepped away" wordmark.
    func defaultVeilImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // 1. Dark elegant gradient background
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0),
            NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.04, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -45.0)

        // Subtle vignette circle
        let centerPoint = NSPoint(x: size.width / 2.0, y: size.height / 2.0)
        let maxRadius = max(size.width, size.height) * 0.6
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
        let titleFont = NSFont.systemFont(ofSize: min(size.width * 0.06, 72), weight: .bold)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(white: 0.92, alpha: 1.0)
        ]
        let title = "BRB" as NSString
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = NSRect(
            x: (size.width - titleSize.width) / 2.0,
            y: (size.height / 2.0) + 20,
            width: titleSize.width,
            height: titleSize.height
        )
        title.draw(in: titleRect, withAttributes: titleAttributes)

        // 3. Subtitle
        let subtitleFont = NSFont.systemFont(ofSize: min(size.width * 0.02, 22), weight: .medium)
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
        ]
        let subtitle = "Stepped away" as NSString
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        let subtitleRect = NSRect(
            x: (size.width - subtitleSize.width) / 2.0,
            y: titleRect.minY - subtitleSize.height - 12,
            width: subtitleSize.width,
            height: subtitleSize.height
        )
        subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)

        image.unlockFocus()
        return image
    }
}
