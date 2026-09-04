import AppKit
import CoreGraphics

// Génère AppIcon.iconset puis AppIcon.icns : le dessin reprend la silhouette
// de NotchShape, la même que celle rendue par l'app.

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let accent = CGColor(red: 0.16, green: 0.62, blue: 1.00, alpha: 1)

/// Coin concave : la silhouette de l'encoche s'évase vers le haut.
func notchPath(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

    path.move(to: CGPoint(x: minX, y: maxY))
    path.addQuadCurve(to: CGPoint(x: minX + top, y: maxY - top),
                      control: CGPoint(x: minX + top, y: maxY))
    path.addLine(to: CGPoint(x: minX + top, y: minY + bottom))
    path.addQuadCurve(to: CGPoint(x: minX + top + bottom, y: minY),
                      control: CGPoint(x: minX + top, y: minY))
    path.addLine(to: CGPoint(x: maxX - top - bottom, y: minY))
    path.addQuadCurve(to: CGPoint(x: maxX - top, y: minY + bottom),
                      control: CGPoint(x: maxX - top, y: minY))
    path.addLine(to: CGPoint(x: maxX - top, y: maxY - top))
    path.addQuadCurve(to: CGPoint(x: maxX, y: maxY),
                      control: CGPoint(x: maxX - top, y: maxY))
    path.closeSubpath()
    return path
}

func render(size: Int) -> Data? {
    let side = CGFloat(size)
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Fond : squircle sombre, marge de sécurité macOS de ~10 %.
    let inset = side * 0.098
    let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = plate.width * 0.2237

    context.saveGState()
    context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(gray: 0.16, alpha: 1), CGColor(gray: 0.03, alpha: 1)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: plate.minX, y: plate.maxY),
                                   end: CGPoint(x: plate.maxX, y: plate.minY),
                                   options: [])
    }
    context.restoreGState()

    // Encoche : hauteur ~38 % de la plaque, accrochée au bord supérieur.
    let notchWidth = plate.width * 0.62
    let notchHeight = plate.height * 0.40
    let notch = CGRect(x: plate.midX - notchWidth / 2,
                       y: plate.maxY - notchHeight,
                       width: notchWidth, height: notchHeight)
    let path = notchPath(in: notch, top: notchWidth * 0.075, bottom: notchWidth * 0.17)

    context.setFillColor(CGColor(gray: 1, alpha: 0.96))
    context.addPath(path)
    context.fillPath()

    // Barre d'accent : le rail d'onglets du panneau, réduit à un trait.
    let barWidth = notchWidth * 0.46
    let bar = CGRect(x: plate.midX - barWidth / 2,
                     y: notch.minY - plate.height * 0.155,
                     width: barWidth, height: plate.height * 0.052)
    context.setFillColor(accent)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2,
                           cornerHeight: bar.height / 2, transform: nil))
    context.fillPath()

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

for (size, name) in variants {
    guard let data = render(size: size) else {
        FileHandle.standardError.write(Data("échec du rendu \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

print("iconset écrit : \(iconset.path)")
