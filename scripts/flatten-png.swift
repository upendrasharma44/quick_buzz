// Removes the alpha channel from PNG files in place (App Store Connect rejects screenshots,
// creative assets and the marketing icon if they contain alpha). Composites onto `--background`
// (default white) first, so any transparent pixels become opaque instead of black.
//
// Usage: swift scripts/flatten-png.swift [--background RRGGBB] <file.png>...
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
var bg: (CGFloat, CGFloat, CGFloat) = (1, 1, 1)
if let i = args.firstIndex(of: "--background"), i + 1 < args.count, let v = UInt32(args[i + 1], radix: 16) {
    bg = (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
    args.removeSubrange(i...(i + 1))
}
guard !args.isEmpty else {
    FileHandle.standardError.write(Data("usage: flatten-png.swift [--background RRGGBB] <file.png>...\n".utf8))
    exit(2)
}

var failed = false
for path in args {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        print("skip \(path): not an image"); failed = true; continue
    }
    let w = image.width, h = image.height
    let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        print("skip \(path): cannot create context"); failed = true; continue
    }
    ctx.setFillColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let flat = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("skip \(path): cannot write"); failed = true; continue
    }
    CGImageDestinationAddImage(dst, flat, nil)
    if CGImageDestinationFinalize(dst) { print("flattened \(path) (\(w)x\(h))") } else { failed = true }
}
exit(failed ? 1 : 0)
