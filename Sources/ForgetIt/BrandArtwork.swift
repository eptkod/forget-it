import SwiftUI
import AppKit

/// One vector drawing is shared by the app, Dock icon, and downloadable artwork.
enum BrandArtwork {
    static let mark = image(size: 256, tile: false)
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func draw(tile: Bool) {
        if tile {
            let tilePath = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 208, yRadius: 208)
            NSGradient(starting: color(0xB5A1EC), ending: color(0x7660B1))!.draw(in: tilePath, angle: 80)
            color(0xFFFFFF).withAlphaComponent(0.18).setStroke(); tilePath.lineWidth = 3; tilePath.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        let tilt = NSAffineTransform(); tilt.translateX(by: 512, yBy: 512); tilt.rotate(byDegrees: -7); tilt.translateX(by: -512, yBy: -512); tilt.concat()
        // A soft offset sheet gives the character a little depth without tiny detail.
        let back = NSBezierPath(roundedRect: NSRect(x: 246, y: 245, width: 494, height: 531), xRadius: 52, yRadius: 52)
        color(tile ? 0x604B9A : 0xB5A1EC).withAlphaComponent(tile ? 0.35 : 0.55).setFill(); back.fill()
        let paper = NSBezierPath()
        paper.move(to: NSPoint(x: 324, y: 216))
        paper.line(to: NSPoint(x: 618, y: 216))
        paper.line(to: NSPoint(x: 754, y: 354))
        paper.line(to: NSPoint(x: 754, y: 720))
        paper.curve(to: NSPoint(x: 696, y: 778), controlPoint1: NSPoint(x: 754, y: 776), controlPoint2: NSPoint(x: 729, y: 800))
        paper.line(to: NSPoint(x: 627, y: 737))
        paper.curve(to: NSPoint(x: 572, y: 737), controlPoint1: NSPoint(x: 608, y: 725), controlPoint2: NSPoint(x: 590, y: 725))
        paper.line(to: NSPoint(x: 510, y: 778))
        paper.curve(to: NSPoint(x: 455, y: 778), controlPoint1: NSPoint(x: 491, y: 791), controlPoint2: NSPoint(x: 474, y: 791))
        paper.line(to: NSPoint(x: 385, y: 736))
        paper.curve(to: NSPoint(x: 332, y: 742), controlPoint1: NSPoint(x: 366, y: 724), controlPoint2: NSPoint(x: 350, y: 730))
        paper.curve(to: NSPoint(x: 270, y: 701), controlPoint1: NSPoint(x: 295, y: 765), controlPoint2: NSPoint(x: 270, y: 745))
        paper.line(to: NSPoint(x: 270, y: 272))
        paper.curve(to: NSPoint(x: 324, y: 216), controlPoint1: NSPoint(x: 270, y: 239), controlPoint2: NSPoint(x: 292, y: 216))
        paper.close()
        NSGradient(starting: color(0xFFFEF5), ending: color(0xF0EAFB))!.draw(in: paper, angle: 90)
        let fold = NSBezierPath(); fold.move(to: NSPoint(x: 618, y: 216)); fold.line(to: NSPoint(x: 618, y: 311))
        fold.curve(to: NSPoint(x: 662, y: 354), controlPoint1: NSPoint(x: 618, y: 341), controlPoint2: NSPoint(x: 631, y: 354))
        fold.line(to: NSPoint(x: 754, y: 354)); fold.close()
        color(0xD4C7EE).setFill(); fold.fill()
        // A cheery bookmark; the face stays legible down to small icon sizes.
        let tab = NSBezierPath(); tab.move(to: NSPoint(x: 353, y: 216)); tab.line(to: NSPoint(x: 353, y: 343)); tab.line(to: NSPoint(x: 394, y: 316)); tab.line(to: NSPoint(x: 435, y: 343)); tab.line(to: NSPoint(x: 435, y: 216)); tab.close()
        color(0xEDB966).setFill(); tab.fill()
        color(0x493961).setFill()
        NSBezierPath(ovalIn: NSRect(x: 378, y: 447, width: 35, height: 49)).fill()
        let wink = NSBezierPath(); wink.move(to: NSPoint(x: 578, y: 467)); wink.curve(to: NSPoint(x: 629, y: 467), controlPoint1: NSPoint(x: 594, y: 448), controlPoint2: NSPoint(x: 614, y: 448))
        stroke(wink, hex: 0x493961, width: 16)
        let smile = NSBezierPath(); smile.move(to: NSPoint(x: 448, y: 541)); smile.curve(to: NSPoint(x: 562, y: 541), controlPoint1: NSPoint(x: 478, y: 584), controlPoint2: NSPoint(x: 531, y: 584))
        stroke(smile, hex: 0x493961, width: 16)
        color(0xE3B3B3).withAlphaComponent(0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: 345, y: 511, width: 56, height: 22)).fill()
        NSBezierPath(ovalIn: NSRect(x: 616, y: 511, width: 56, height: 22)).fill()
        let line = NSBezierPath(); line.move(to: NSPoint(x: 418, y: 655)); line.line(to: NSPoint(x: 584, y: 655)); stroke(line, hex: 0xD0C3E7, width: 14)
        NSGraphicsContext.restoreGraphicsState()
        let spark = NSBezierPath(); spark.move(to: NSPoint(x: 794, y: 196)); spark.curve(to: NSPoint(x: 834, y: 248), controlPoint1: NSPoint(x: 799, y: 230), controlPoint2: NSPoint(x: 805, y: 241)); spark.curve(to: NSPoint(x: 789, y: 294), controlPoint1: NSPoint(x: 804, y: 253), controlPoint2: NSPoint(x: 793, y: 265)); spark.curve(to: NSPoint(x: 750, y: 244), controlPoint1: NSPoint(x: 783, y: 264), controlPoint2: NSPoint(x: 776, y: 253)); spark.curve(to: NSPoint(x: 794, y: 196), controlPoint1: NSPoint(x: 779, y: 239), controlPoint2: NSPoint(x: 788, y: 225)); spark.close()
        color(0xF8D48E).setFill(); spark.fill()
    }
    private static func stroke(_ path: NSBezierPath, hex: UInt32, width: CGFloat) {
        color(hex).setStroke(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
    }
    static func image(size: Int, tile: Bool) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: CGFloat(size)); transform.scaleX(by: CGFloat(size) / 1024, yBy: -CGFloat(size) / 1024); transform.concat()
        draw(tile: tile)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size, height: size)); image.addRepresentation(bitmap)
        return image
    }
}

struct BrandMark: View {
    var body: some View {
        Image(nsImage: BrandArtwork.mark).resizable().interpolation(.high).scaledToFit().accessibilityLabel("forget it paper mascot")
    }
}
