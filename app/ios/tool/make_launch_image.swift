// Génère le logo de l'écran de lancement iOS (LaunchImage.imageset) : logo
// « hémicycle en bandes » de make_app_icon.swift, sans fond, 120 × 60 pt.
// - clair : encre #15181C, vert #1D6B54 ;
// - sombre : encre #ECEEF0, vert #4FB08F.
// Le fond (couleur nommée LaunchBackground) est dans le storyboard.
//
// Depuis app/ios : swift tool/make_launch_image.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let imageSet = URL(fileURLWithPath: "Runner/Assets.xcassets/LaunchImage.imageset")

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Taille en points : le logo (104 × 52 dans la grille de 120 des maquettes,
/// arcs de rayon 46 et 28 centrés en (60, 86), épaisseur 12) mis à 120 pt.
let widthPt = 120.0
let heightPt = 60.0

func render(scale: Int, ink: UInt32, accent: UInt32) -> CGImage {
  let width = Int(widthPt) * scale
  let height = Int(heightPt) * scale
  let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  // Repère SVG (y vers le bas) ; boîte du logo : x 8…112, y 34…86.
  let unit = CGFloat(width) / 104
  ctx.translateBy(x: 0, y: CGFloat(height))
  ctx.scaleBy(x: unit, y: -unit)
  ctx.translateBy(x: -8, y: -34)
  ctx.setStrokeColor(rgb(ink))
  ctx.setLineWidth(12)
  ctx.setLineCap(.butt)
  for radius in [46.0, 28.0] {
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: 60, y: 86), radius: radius, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
  }
  ctx.setFillColor(rgb(accent))
  ctx.beginPath()
  ctx.addArc(center: CGPoint(x: 60, y: 86), radius: 12, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
  ctx.closePath()
  ctx.fillPath()
  return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, nil)
  precondition(CGImageDestinationFinalize(dest), "écriture de \(url.path)")
}

for (suffix, ink, accent) in [("", UInt32(0x15181C), UInt32(0x1D6B54)), ("Dark", 0xECEEF0, 0x4FB08F)] {
  for scale in 1...3 {
    let name = "LaunchImage\(suffix)\(scale == 1 ? "" : "@\(scale)x").png"
    write(render(scale: scale, ink: ink, accent: accent), to: imageSet.appendingPathComponent(name))
    print(name)
  }
}
