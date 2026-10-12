import AppKit

func makeRep(scale: CGFloat) -> NSBitmapImageRep {
    let width: CGFloat = 600
    let height: CGFloat = 420
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Draw background gradient: clean macOS Light theme
    let bgRect = NSRect(x: 0, y: 0, width: width, height: height)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.968, green: 0.970, blue: 0.975, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.918, green: 0.922, blue: 0.932, alpha: 1.0)
    )
    gradient?.draw(in: bgRect, angle: -90)

    // Subtle border
    let borderPath = NSBezierPath(rect: bgRect)
    NSColor(calibratedWhite: 0.82, alpha: 1.0).setStroke()
    borderPath.lineWidth = 1
    borderPath.stroke()

    // Header: Title at top (y = height - 55)
    let title = "Install BRB"
    let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    let titleRect = NSRect(x: (width - titleSize.width) / 2, y: height - 55, width: titleSize.width, height: titleSize.height)
    title.draw(in: titleRect, withAttributes: titleAttrs)

    // Header: Subtitle (y = height - 82)
    let subtitle = "Drag BRB into the Applications folder"
    let subFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(calibratedRed: 0.43, green: 0.43, blue: 0.45, alpha: 1.0)
    ]
    let subSize = subtitle.size(withAttributes: subAttrs)
    let subRect = NSRect(x: (width - subSize.width) / 2, y: height - 82, width: subSize.width, height: subSize.height)
    subtitle.draw(in: subRect, withAttributes: subAttrs)

    // Pedestals behind icons:
    // In Finder, icon center is 180pt from the top -> y = height - 180 from bottom!
    let iconCenterY = height - 180
    let leftPedestalRect = NSRect(x: 150 - 58, y: iconCenterY - 58, width: 116, height: 116)
    let rightPedestalRect = NSRect(x: 450 - 58, y: iconCenterY - 58, width: 116, height: 116)

    for r in [leftPedestalRect, rightPedestalRect] {
        let path = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
        NSColor(white: 1.0, alpha: 0.75).setFill()
        path.fill()

        let strokePath = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
        let pattern: [CGFloat] = [5, 4]
        strokePath.setLineDash(pattern, count: 2, phase: 0)
        strokePath.lineWidth = 1.5
        NSColor(calibratedWhite: 0.76, alpha: 0.8).setStroke()
        strokePath.stroke()
    }

    // Modern accent blue arrow in the middle
    let arrowPath = NSBezierPath()
    arrowPath.move(to: NSPoint(x: 270, y: iconCenterY))
    arrowPath.line(to: NSPoint(x: 326, y: iconCenterY))
    arrowPath.line(to: NSPoint(x: 314, y: iconCenterY + 10))
    arrowPath.move(to: NSPoint(x: 326, y: iconCenterY))
    arrowPath.line(to: NSPoint(x: 314, y: iconCenterY - 10))
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    arrowPath.lineWidth = 3.5
    NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.95).setStroke()
    arrowPath.stroke()

    // Bottom Card: Clear guidance on Gatekeeper and where to run the command
    let cardW: CGFloat = 510
    let cardH: CGFloat = 64
    let cardY: CGFloat = 46 // Placed 46pt above the bottom edge so it is never clipped
    let cardRect = NSRect(x: (width - cardW) / 2, y: cardY, width: cardW, height: cardH)

    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 10, yRadius: 10)
    NSColor(white: 1.0, alpha: 0.95).setFill()
    cardPath.fill()
    NSColor(calibratedWhite: 0.82, alpha: 1.0).setStroke()
    cardPath.lineWidth = 1
    cardPath.stroke()

    // Instruction label
    let tipText = "If blocked on first launch: open Terminal and run this command:"
    let tipFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
    let tipAttrs: [NSAttributedString.Key: Any] = [
        .font: tipFont,
        .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.38, alpha: 1.0)
    ]
    let tipSize = tipText.size(withAttributes: tipAttrs)
    let tipRect = NSRect(x: (width - tipSize.width) / 2, y: cardY + cardH - 22, width: tipSize.width, height: tipSize.height)
    tipText.draw(in: tipRect, withAttributes: tipAttrs)

    // Command box
    let cmdPillW: CGFloat = 340
    let cmdPillH: CGFloat = 24
    let cmdPillY = cardY + 9
    let cmdPillRect = NSRect(x: (width - cmdPillW) / 2, y: cmdPillY, width: cmdPillW, height: cmdPillH)
    let cmdPillPath = NSBezierPath(roundedRect: cmdPillRect, xRadius: 6, yRadius: 6)
    NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.98, alpha: 1.0).setFill()
    cmdPillPath.fill()
    NSColor(calibratedRed: 0.85, green: 0.88, blue: 0.95, alpha: 1.0).setStroke()
    cmdPillPath.lineWidth = 1
    cmdPillPath.stroke()

    let cmdText = "xattr -cr /Applications/BRB.app"
    let cmdFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    let cmdAttrs: [NSAttributedString.Key: Any] = [
        .font: cmdFont,
        .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.88, alpha: 1.0)
    ]
    let cmdSize = cmdText.size(withAttributes: cmdAttrs)
    let cmdRect = NSRect(x: (width - cmdSize.width) / 2, y: cmdPillY + (cmdPillH - cmdSize.height) / 2, width: cmdSize.width, height: cmdSize.height)
    cmdText.draw(in: cmdRect, withAttributes: cmdAttrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let repoRoot = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let targetDir = "\(repoRoot)/scripts/assets"
let targetTIFF = "\(targetDir)/dmg-background.tiff"
let targetPNG = "\(targetDir)/dmg-background.png"

let rep1x = makeRep(scale: 1.0)
let rep2x = makeRep(scale: 2.0)

let tmp1x = "/tmp/brb_dmg_bg_1x.png"
let tmp2x = "/tmp/brb_dmg_bg_2x.png"

let png1 = rep1x.representation(using: .png, properties: [:])!
let png2 = rep2x.representation(using: .png, properties: [:])!
try! png1.write(to: URL(fileURLWithPath: tmp1x))
try! png2.write(to: URL(fileURLWithPath: tmp2x))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
process.arguments = ["-cathidpicheck", tmp1x, tmp2x, "-out", targetTIFF]
try! process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(atPath: targetPNG)
try? FileManager.default.copyItem(atPath: tmp2x, toPath: targetPNG)

print("Generated properly oriented background at \(targetTIFF) and \(targetPNG)")
