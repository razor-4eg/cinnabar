import CoreGraphics
import Foundation
import ImageIO

let size = 1024
guard CommandLine.arguments.count > 1 else {
    fputs("usage: make-icon.swift output.png\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    exit(1)
}

let colors = [
    CGColor(red: 1.0, green: 0.45, blue: 0.36, alpha: 1),
    CGColor(red: 0.55, green: 0.07, blue: 0.12, alpha: 1)
] as CFArray
guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else {
    exit(1)
}
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 120, y: 980),
    end: CGPoint(x: 900, y: 40),
    options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
)

let vignetteColors = [
    CGColor(red: 0, green: 0, blue: 0, alpha: 0),
    CGColor(red: 0.28, green: 0, blue: 0.03, alpha: 0.38)
] as CFArray
if let vignette = CGGradient(colorsSpace: colorSpace, colors: vignetteColors, locations: [0.62, 1]) {
    context.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: 512, y: 620),
        startRadius: 40,
        endCenter: CGPoint(x: 512, y: 480),
        endRadius: 760,
        options: [.drawsAfterEndLocation]
    )
}

context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -12),
    blur: 28,
    color: CGColor(red: 0.32, green: 0, blue: 0.04, alpha: 0.28)
)
strokeArrow(in: context)
context.restoreGState()

guard let image = context.makeImage() else { exit(1) }
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }

func strokeArrow(in context: CGContext) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 730))
    path.addLine(to: CGPoint(x: 512, y: 360))
    path.move(to: CGPoint(x: 300, y: 530))
    path.addLine(to: CGPoint(x: 512, y: 300))
    path.addLine(to: CGPoint(x: 724, y: 530))
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(96)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.strokePath()
}
