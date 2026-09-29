import AppKit

@main struct MakeIcon {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let exports = URL(fileURLWithPath: "assets/brand")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
            try png(size: pixels, tile: true).write(to: root.appendingPathComponent(name + ".png"))
        }
        try png(size: 2048, tile: true).write(to: exports.appendingPathComponent("forget-it-icon.png"))
        try png(size: 2048, tile: false).write(to: exports.appendingPathComponent("forget-it-mascot-transparent.png"))
        let view = ArtworkView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        try view.dataWithPDF(inside: view.bounds).write(to: exports.appendingPathComponent("forget-it-logo-vector.pdf"))
        print("Exported app icon, transparent mascot, and vector PDF.")
    }
    static func png(size: Int, tile: Bool) -> Data {
        let image = BrandArtwork.image(size: size, tile: tile)
        return (image.representations[0] as! NSBitmapImageRep).representation(using: .png, properties: [:])!
    }
}
final class ArtworkView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { BrandArtwork.draw(tile: false) }
}
