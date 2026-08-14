import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

for pixels in sizes {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No graphics context") }
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)

    let page = CGMutablePath()
    page.move(to: CGPoint(x: 236, y: 106))
    page.addLine(to: CGPoint(x: 660, y: 106))
    page.addLine(to: CGPoint(x: 812, y: 258))
    page.addLine(to: CGPoint(x: 812, y: 918))
    page.addLine(to: CGPoint(x: 236, y: 918))
    page.closeSubpath()
    context.addPath(page)
    context.setFillColor(NSColor.white.cgColor)
    context.setShadow(offset: CGSize(width: 0, height: -20), blur: 36, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 660, y: 106))
    fold.addLine(to: CGPoint(x: 660, y: 258))
    fold.addLine(to: CGPoint(x: 812, y: 258))
    fold.closeSubpath()
    context.addPath(fold)
    context.setFillColor(NSColor(calibratedRed: 0.74, green: 0.81, blue: 0.96, alpha: 1).cgColor)
    context.fillPath()

    context.setLineCap(.round)
    context.setStrokeColor(NSColor(calibratedRed: 0.19, green: 0.39, blue: 0.88, alpha: 1).cgColor)
    context.setLineWidth(60)
    context.move(to: CGPoint(x: 350, y: 700))
    context.addLine(to: CGPoint(x: 470, y: 700))
    context.strokePath()

    context.setStrokeColor(NSColor(calibratedWhite: 0.25, alpha: 1).cgColor)
    context.setLineWidth(38)
    for (start, end, y) in [(350, 704, 565), (350, 650, 455), (350, 730, 345)] {
        context.move(to: CGPoint(x: start, y: y))
        context.addLine(to: CGPoint(x: end, y: y))
        context.strokePath()
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { fatalError("Could not encode icon") }
    try png.write(to: output.appendingPathComponent("icon_\(pixels).png"))
}

