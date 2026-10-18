// Génère l'icône iOS Hémicycle (#29) : logo clair #F3F4F5 (deux rangées de
// sièges en demi-cercle) sur fond graphite #15181C, opaque, puis les tailles
// de AppIcon.appiconset.
//
// Depuis app/ios : swift tool/make_app_icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconSet = URL(fileURLWithPath: "Runner/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Positions régulières, extrémités comprises (même règle que
/// `VoteArc.dotPositions` du widget).
func dotPositions(length: Double, spacing: Double) -> [Double] {
  let gaps = max(1, Int((length / spacing).rounded()))
  return (0...gaps).map { Double($0) / Double(gaps) }
}

func render(size: Int) -> CGImage {
  let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.setFillColor(rgb(0x15181C))
  ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

  // Maquette (Main.dc.html) : logo de 84 px de large dans une icône de 120,
  // repère 120 × 66, rangées de rayon 54 et 38, points de 7 tous les 12,1.
  let side = CGFloat(size)
  let scale = side * 0.7 / 120
  let originX = (side - 120 * scale) / 2
  let originY = (side - 66 * scale) / 2
  ctx.setFillColor(rgb(0xF3F4F5))
  for radius in [54.0, 38.0] {
    for t in dotPositions(length: .pi * radius, spacing: 12.1) {
      let angle = Double.pi * (1 + t)
      let x = 60 + radius * cos(angle)
      let y = 60 + radius * sin(angle)  // repère SVG, y vers le bas
      let d = 7 * scale
      let cx = originX + CGFloat(x) * scale
      let cy = side - (originY + CGFloat(y) * scale)  // CoreGraphics, y vers le haut
      ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
    }
  }
  return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, nil)
  precondition(CGImageDestinationFinalize(dest), "écriture de \(url.path)")
}

// Fichiers attendus par Contents.json : (nom, côté en pixels).
let data = try Data(contentsOf: iconSet.appendingPathComponent("Contents.json"))
let contents = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for image in contents["images"] as! [[String: Any]] {
  guard let filename = image["filename"] as? String,
    let size = (image["size"] as? String)?.split(separator: "x").first.flatMap({ Double($0) }),
    let scale = (image["scale"] as? String).flatMap({ Double($0.dropLast()) })
  else { continue }
  let pixels = Int((size * scale).rounded())
  write(render(size: pixels), to: iconSet.appendingPathComponent(filename))
  print("\(filename) \(pixels) px")
}
