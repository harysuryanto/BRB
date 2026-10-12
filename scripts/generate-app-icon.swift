import AppKit
import CoreGraphics

// MARK: - Light Theme Canvas Helpers

func createLightTileCanvas(ctx: CGContext, tileRect: NSRect, cornerRadius: CGFloat) {
    let squirclePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Deep elevation shadow
    ctx.saveGState()
    let deepShadowColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18).cgColor
    ctx.setShadow(offset: CGSize(width: 0, height: -28), blur: 36, color: deepShadowColor)
    NSColor(white: 0.98, alpha: 1.0).setFill()
    squirclePath.fill()
    ctx.restoreGState()

    // Ambient contact shadow
    ctx.saveGState()
    let contactShadowColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10).cgColor
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 12, color: contactShadowColor)
    NSColor(white: 0.98, alpha: 1.0).setFill()
    squirclePath.fill()
    ctx.restoreGState()

    // Squircle Interior Clip
    ctx.saveGState()
    squirclePath.addClip()

    // Clean Apple Light Theme gradient: pure white top fading into soft silver-white bottom
    let baseGradient = NSGradient(
        colorsAndLocations:
        (NSColor(srgbRed: 0.995, green: 0.998, blue: 1.0, alpha: 1.0), 0.0),
        (NSColor(srgbRed: 0.965, green: 0.972, blue: 0.985, alpha: 1.0), 0.5),
        (NSColor(srgbRed: 0.925, green: 0.935, blue: 0.952, alpha: 1.0), 1.0)
    )
    baseGradient?.draw(in: tileRect, angle: -90)
}

func finishLightTile(ctx: CGContext, tileRect: NSRect, cornerRadius: CGFloat) {
    ctx.restoreGState()

    let squirclePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    squirclePath.lineWidth = 1.5
    NSColor(calibratedWhite: 0.78, alpha: 0.6).setStroke()
    squirclePath.stroke()
}

// MARK: - App Icon: Signal & Lock (Light Minimalist)

func renderAppIcon() -> NSImage {
    let size: CGFloat = 1024.0
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true); ctx.interpolationQuality = .high

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185.0

    createLightTileCanvas(ctx: ctx, tileRect: tileRect, cornerRadius: cornerRadius)

    let center = CGPoint(x: 512, y: 512)

    // Concentric Proximity Signal Waves (Left & Right AirDrop Wings)
    for (i, r) in [205.0, 275.0, 345.0].enumerated() {
        ctx.saveGState()
        let alpha = [0.85, 0.55, 0.28][i]
        let width: CGFloat = [6.0, 5.0, 4.0][i]
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: alpha).cgColor)

        // Right arc
        let rightArc = CGMutablePath()
        rightArc.addArc(center: center, radius: r, startAngle: -CGFloat.pi * 0.22, endAngle: CGFloat.pi * 0.22, clockwise: false)
        ctx.addPath(rightArc)
        ctx.strokePath()

        // Left arc
        let leftArc = CGMutablePath()
        leftArc.addArc(center: center, radius: r, startAngle: CGFloat.pi * 0.78, endAngle: CGFloat.pi * 1.22, clockwise: false)
        ctx.addPath(leftArc)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Center Privacy Shield Badge: 290 wide x 340 high
    let badgeRect = CGRect(x: 512 - 145, y: 512 - 170, width: 290, height: 340)
    let badgePath = CGMutablePath()
    let bCrest = CGPoint(x: 512, y: badgeRect.maxY)
    let bShoulderR = CGPoint(x: badgeRect.maxX, y: badgeRect.maxY - 25)
    let bShoulderL = CGPoint(x: badgeRect.minX, y: badgeRect.maxY - 25)
    let bWaistR = CGPoint(x: badgeRect.maxX, y: badgeRect.minY + 125)
    let bWaistL = CGPoint(x: badgeRect.minX, y: badgeRect.minY + 125)
    let bTip = CGPoint(x: 512, y: badgeRect.minY)

    badgePath.move(to: bCrest)
    badgePath.addCurve(to: bShoulderR, control1: CGPoint(x: 560, y: bCrest.y), control2: CGPoint(x: 625, y: bCrest.y - 10))
    badgePath.addCurve(to: bWaistR, control1: CGPoint(x: badgeRect.maxX, y: badgeRect.maxY - 80), control2: CGPoint(x: badgeRect.maxX, y: bWaistR.y + 40))
    badgePath.addCurve(to: bTip, control1: CGPoint(x: badgeRect.maxX - 5, y: bTip.y + 70), control2: CGPoint(x: 580, y: bTip.y))
    badgePath.addCurve(to: bWaistL, control1: CGPoint(x: 444, y: bTip.y), control2: CGPoint(x: badgeRect.minX + 5, y: bTip.y + 70))
    badgePath.addCurve(to: bShoulderL, control1: CGPoint(x: badgeRect.minX, y: bWaistL.y + 40), control2: CGPoint(x: badgeRect.minX, y: badgeRect.maxY - 80))
    badgePath.addCurve(to: bCrest, control1: CGPoint(x: 399, y: bCrest.y - 10), control2: CGPoint(x: 464, y: bCrest.y))
    badgePath.closeSubpath()

    // Badge Drop Shadow onto white tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 28, color: NSColor(srgbRed: 0.0, green: 0.22, blue: 0.60, alpha: 0.38).cgColor)
    ctx.addPath(badgePath)
    ctx.setFillColor(NSColor(srgbRed: 0.0, green: 0.45, blue: 0.95, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Badge Fill: Apple System Blue Gradient
    ctx.saveGState()
    ctx.addPath(badgePath)
    ctx.clip()

    let badgeGradColors = [
        NSColor(srgbRed: 0.05, green: 0.58, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.00, green: 0.42, blue: 0.95, alpha: 1.0).cgColor,
        NSColor(srgbRed: 0.00, green: 0.28, blue: 0.80, alpha: 1.0).cgColor
    ] as CFArray
    if let bGrad = CGGradient(colorsSpace: colorSpace, colors: badgeGradColors, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(bGrad, start: CGPoint(x: 512, y: badgeRect.maxY), end: CGPoint(x: 512, y: badgeRect.minY), options: [])
    }

    // Badge Rim Highlight
    ctx.saveGState()
    ctx.addPath(badgePath)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.45).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Inside Badge: Minimalist Lock / Privacy Shield Motif in pure crisp white
    let lockCenter = CGPoint(x: 512, y: 520)
    let shacklePath = CGMutablePath()
    let shackleW: CGFloat = 66.0
    let shackleH: CGFloat = 60.0
    shacklePath.move(to: CGPoint(x: lockCenter.x - shackleW / 2, y: lockCenter.y + 10))
    shacklePath.addLine(to: CGPoint(x: lockCenter.x - shackleW / 2, y: lockCenter.y + shackleH))
    shacklePath.addArc(
        center: CGPoint(x: lockCenter.x, y: lockCenter.y + shackleH),
        radius: shackleW / 2,
        startAngle: CGFloat.pi,
        endAngle: 0,
        clockwise: true
    )
    shacklePath.addLine(to: CGPoint(x: lockCenter.x + shackleW / 2, y: lockCenter.y + 10))

    ctx.saveGState()
    ctx.setLineWidth(13.0)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.addPath(shacklePath)
    ctx.strokePath()
    ctx.restoreGState()

    // Lock Body
    let lockBodyRect = CGRect(x: lockCenter.x - 50, y: lockCenter.y - 70, width: 100, height: 82)
    let lockBodyPath = CGPath(roundedRect: lockBodyRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(lockBodyPath)
    ctx.fillPath()

    // Keyhole Cutout (Dark Blue)
    let keyholeCircle = CGRect(x: lockCenter.x - 9, y: lockCenter.y - 32, width: 18, height: 18)
    ctx.setFillColor(NSColor(srgbRed: 0.00, green: 0.32, blue: 0.80, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: keyholeCircle)
    let keyholeStem = CGRect(x: lockCenter.x - 4.5, y: lockCenter.y - 52, width: 9, height: 22)
    ctx.fill(keyholeStem)
    ctx.restoreGState()

    ctx.restoreGState() // unclip badge

    finishLightTile(ctx: ctx, tileRect: tileRect, cornerRadius: cornerRadius)

    image.unlockFocus()
    return image
}

// MARK: - Resizing & Asset Catalog Export

func resizeImage(master: NSImage, pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    master.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: NSRect(x: 0, y: 0, width: master.size.width, height: master.size.height),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for size \(pixelSize)")
    }
    return png
}

// MARK: - Main Execution

let repoRoot = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let appIconSetDir = "\(repoRoot)/BRB/Assets.xcassets/AppIcon.appiconset"
let scriptsAssetsDir = "\(repoRoot)/scripts/assets"

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: appIconSetDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(atPath: scriptsAssetsDir, withIntermediateDirectories: true)

print("🎨 Rendering BRB app icon (Signal & Lock)...")
let master = renderAppIcon()

struct IconSpec {
    let size: Int
    let scale: Int
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
    var pixelSize: Int { size * scale }
}

let specs: [IconSpec] = [
    IconSpec(size: 16, scale: 1),
    IconSpec(size: 16, scale: 2),
    IconSpec(size: 32, scale: 1),
    IconSpec(size: 32, scale: 2),
    IconSpec(size: 128, scale: 1),
    IconSpec(size: 128, scale: 2),
    IconSpec(size: 256, scale: 1),
    IconSpec(size: 256, scale: 2),
    IconSpec(size: 512, scale: 1),
    IconSpec(size: 512, scale: 2),
]

let tmpIconsetDir = "/tmp/BRB.iconset"
try? fileManager.removeItem(atPath: tmpIconsetDir)
try! fileManager.createDirectory(atPath: tmpIconsetDir, withIntermediateDirectories: true)

print("📦 Exporting icon resolutions to AppIcon.appiconset...")
for spec in specs {
    let pngData = resizeImage(master: master, pixelSize: spec.pixelSize)
    let appIconPath = "\(appIconSetDir)/\(spec.filename)"
    try! pngData.write(to: URL(fileURLWithPath: appIconPath))

    let iconsetPath = "\(tmpIconsetDir)/\(spec.filename)"
    try! pngData.write(to: URL(fileURLWithPath: iconsetPath))
}

let contentsJson: [String: Any] = [
    "images": specs.map { spec in
        [
            "filename": spec.filename,
            "idiom": "mac",
            "scale": "\(spec.scale)x",
            "size": "\(spec.size)x\(spec.size)"
        ]
    },
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

let jsonData = try! JSONSerialization.data(withJSONObject: contentsJson, options: [.prettyPrinted, .sortedKeys])
try! jsonData.write(to: URL(fileURLWithPath: "\(appIconSetDir)/Contents.json"))
print("📄 Updated \(appIconSetDir)/Contents.json")

let icnsTarget = "\(scriptsAssetsDir)/AppIcon.icns"
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", tmpIconsetDir, "-o", icnsTarget]
try! iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("💎 Generated \(icnsTarget)")
}

try? fileManager.removeItem(atPath: tmpIconsetDir)
print("✅ Complete!")
